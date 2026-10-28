import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/fishery/fish_category.dart';
import '../../features/fishery/fish_sale.dart';
import '../../features/spare_parts/inventory/category.dart';
import '../../features/spare_parts/inventory/product.dart';
import '../system/audit_log.dart';
import '../../features/spare_parts/purchases/purchase.dart';
import '../../features/spare_parts/sales/refund.dart';
import '../../features/spare_parts/sales/sale.dart';
import '../../features/transport/contract.dart';
import '../../features/transport/monthly_settlement.dart';
import '../../features/transport/trip_income.dart';
import '../../features/transport/vehicle_khata_line.dart';
import '../../features/transport/weight_entry.dart';
import '../accounting/approval_threshold.dart';
import '../accounting/bank_account.dart';
import '../accounting/chart_of_accounts_seed.dart';
import '../accounting/fixed_asset.dart';
import '../accounting/fiscal_period.dart';
import '../accounting/journal_entry.dart';
import '../accounting/ledger_repository.dart';
import '../accounting/tax_rate.dart';
import '../activity/trip.dart';
import '../activity/trip_expense.dart';
import '../asset/operating_asset.dart';
import '../party/party.dart';
import '../system/number_sequence_service.dart';
import '../tenant/business.dart';
import '../transaction/payment.dart';
import '../transaction/salary_record.dart';
import 'conflict_record_repository.dart';
import 'sync_queue_item.dart';
import 'sync_queue_repository.dart';

class DownloadResult {
  DownloadResult({required this.inserted, required this.statusUpdated, required this.conflicts});
  final int inserted;
  final int statusUpdated;
  final int conflicts;
}

/// The sync engine described in PHASES.md Phase 5. No Cloud Functions
/// (free Spark plan): atomic document numbering uses a Firestore
/// client-side `runTransaction` against a counter document instead of a
/// server-side function, and there's no server-side balance
/// re-validation (already enforced client-side before anything reaches
/// this far — see `JournalEntry.isBalanced`/`LedgerRepository.postWithin`).
///
/// [uploadPending] is the local-to-remote half; [downloadAndMerge] is
/// remote-to-local. JournalEntry lines are immutable once posted (see
/// PHASES.md Section 11 — "Reversal, not edit"), so the only thing that
/// can actually disagree between two devices' copies of the same entry is
/// its `status` (posted/reversed/void_). That makes merge conflicts much
/// narrower than the general case: see [downloadAndMerge]'s status-merge
/// logic.
class FirestoreSyncService {
  FirestoreSyncService({
    required this.db,
    required this.firestore,
    required this.syncQueue,
    required this.ledger,
    required this.conflictRecords,
    this.numbering,
  });

  final Database db;
  final FirebaseFirestore firestore;
  final SyncQueueRepository syncQueue;
  final LedgerRepository ledger;
  final ConflictRecordRepository conflictRecords;

  /// Optional — only needed for [restoreFromCloud]'s document-numbering
  /// fix-up (see [NumberSequenceService.resyncFromIssuedNumbers]).
  /// Omitting it (existing tests that construct this service without it)
  /// just means that one fix-up step is skipped, not that restore fails.
  final NumberSequenceService? numbering;

  /// Upload then download — the one call both the manual "Sync Now"
  /// button and any periodic/foreground trigger should use, so both
  /// directions always run together rather than callers having to
  /// remember to call both.
  Future<DownloadResult> syncAll(String businessId) async {
    if (!_backfilledThisSession.contains(businessId)) {
      _backfilledThisSession.add(businessId);
      await backfillSyncQueue(businessId);
    }
    await uploadPending(businessId);
    return downloadAndMerge(businessId);
  }

  /// Businesses already backfilled once in this app session — a guard
  /// against [backfillSyncQueue]'s table scans running on every
  /// `syncAll()` call (the 3-minute background timer, every foreground
  /// resume, the manual "Sync Now" button all call it); this instance
  /// lives for the app's lifetime (FirestoreSyncService isn't
  /// `autoDispose`d), so the guard holds for the whole session.
  final Set<String> _backfilledThisSession = {};

  /// Uploads every pending/failed queue item for [businessId]. Returns
  /// the number of items successfully synced. Items that fail (offline,
  /// permission denied, etc.) are marked `failed` with the error and
  /// left for the next call to retry — see SyncQueueRepository.markFailed.
  Future<int> uploadPending(String businessId) async {
    final items = await syncQueue.pending(businessId: businessId);
    var succeeded = 0;

    for (final item in items) {
      try {
        switch (item.entityType) {
          case 'JournalEntry':
            await _uploadJournalEntry(businessId, item);
            break;
          case 'Party':
            await _uploadParty(businessId, item);
            break;
          case 'Product':
            await _uploadProduct(businessId, item);
            break;
          case 'Business':
            await _uploadBusiness(item);
            break;
          case 'Purchase':
            await _uploadPurchase(businessId, item);
            break;
          case 'Sale':
            await _uploadSale(businessId, item);
            break;
          case 'Refund':
            await _uploadRefund(businessId, item);
            break;
          case 'Category':
            await _uploadFlat(collection: 'categories', table: Category.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) { final c = Category.fromMap(r); return {'uuid': c.uuid, 'businessId': c.businessId, 'name': c.name, 'isActive': c.isActive}; });
            break;
          case 'Brand':
            await _uploadFlat(collection: 'brands', table: Brand.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) { final b = Brand.fromMap(r); return {'uuid': b.uuid, 'businessId': b.businessId, 'name': b.name, 'isActive': b.isActive}; });
            break;
          case 'OperatingAsset':
            await _uploadFlat(collection: 'operatingAssets', table: OperatingAsset.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final a = OperatingAsset.fromMap(r);
                  return {'uuid': a.uuid, 'businessId': a.businessId, 'type': a.type.name, 'name': a.name, 'registrationNumber': a.registrationNumber, 'isActive': a.isActive};
                });
            break;
          case 'Trip':
            await _uploadFlat(collection: 'trips', table: Trip.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final t = Trip.fromMap(r);
                  return {
                    'uuid': t.uuid, 'businessId': t.businessId, 'tripType': t.tripType.name, 'assetUuid': t.assetUuid,
                    'captainUuid': t.captainUuid, 'status': t.status.name, 'startDate': t.startDate.toIso8601String(),
                    'endDate': t.endDate?.toIso8601String(), 'notes': t.notes,
                  };
                });
            break;
          case 'TripExpense':
            await _uploadFlat(collection: 'tripExpenses', table: TripExpense.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final e = TripExpense.fromMap(r);
                  return {
                    'uuid': e.uuid, 'tripUuid': e.tripUuid, 'assetUuid': e.assetUuid, 'businessId': e.businessId,
                    'category': e.category.name, 'amountMinorUnits': e.amountMinorUnits, 'description': e.description,
                    'date': e.date.toIso8601String(),
                  };
                });
            break;
          case 'FishCategory':
            await _uploadFlat(collection: 'fishCategories', table: FishCategory.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) { final c = FishCategory.fromMap(r); return {'uuid': c.uuid, 'businessId': c.businessId, 'name': c.name, 'isActive': c.isActive}; });
            break;
          case 'CatchEntry':
            await _uploadFlat(collection: 'catchEntries', table: CatchEntry.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final c = CatchEntry.fromMap(r);
                  return {
                    'uuid': c.uuid, 'tripUuid': c.tripUuid, 'businessId': c.businessId, 'fishCategoryUuid': c.fishCategoryUuid,
                    'weightKg': c.weightKg, 'estimatedValueMinorUnits': c.estimatedValueMinorUnits,
                  };
                });
            break;
          case 'FishSale':
            await _uploadFlat(collection: 'fishSales', table: FishSale.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final s = FishSale.fromMap(r);
                  return {
                    'uuid': s.uuid, 'businessId': s.businessId, 'tripUuid': s.tripUuid, 'customerUuid': s.customerUuid,
                    'fishCategoryUuid': s.fishCategoryUuid, 'weightKg': s.weightKg,
                    'unitPriceMinorUnitsPerKg': s.unitPriceMinorUnitsPerKg, 'paymentMethod': s.paymentMethod.name,
                    'date': s.date.toIso8601String(),
                  };
                });
            break;
          case 'Contract':
            await _uploadFlat(collection: 'contracts', table: Contract.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final c = Contract.fromMap(r);
                  return {
                    'uuid': c.uuid, 'businessId': c.businessId, 'customerUuid': c.customerUuid, 'description': c.description,
                    'ratePerTripMinorUnits': c.ratePerTripMinorUnits, 'ratePerTonMinorUnits': c.ratePerTonMinorUnits,
                    'isActive': c.isActive, 'startDate': c.startDate.toIso8601String(), 'endDate': c.endDate?.toIso8601String(),
                  };
                });
            break;
          case 'WeightEntry':
            await _uploadFlat(collection: 'weightEntries', table: WeightEntry.tableName, id: item.entityId, businessId: businessId,
                operation: item.operation,
                toDoc: (r) {
                  final e = WeightEntry.fromMap(r);
                  return {
                    'uuid': e.uuid, 'businessId': e.businessId, 'vehicleUuid': e.vehicleUuid, 'companyUuid': e.companyUuid,
                    'date': e.date.toIso8601String(), 'weightKg': e.weightKg, 'notes': e.notes,
                    'settlementUuid': e.settlementUuid, 'amountMinorUnits': e.amountMinorUnits,
                  };
                });
            break;
          case 'MonthlySettlement':
            await _uploadFlat(collection: 'monthlySettlements', table: MonthlySettlement.tableName, id: item.entityId, businessId: businessId,
                operation: item.operation,
                toDoc: (r) {
                  final s = MonthlySettlement.fromMap(r);
                  return {
                    'uuid': s.uuid, 'businessId': s.businessId, 'companyUuid': s.companyUuid, 'year': s.year, 'month': s.month,
                    'ratePerTonMinorUnits': s.ratePerTonMinorUnits, 'totalWeightKg': s.totalWeightKg,
                    'amountMinorUnits': s.amountMinorUnits, 'date': s.date.toIso8601String(),
                  };
                });
            break;
          case 'VehicleKhataLine':
            await _uploadFlat(collection: 'vehicleKhataLines', table: VehicleKhataLine.tableName, id: item.entityId, businessId: businessId,
                operation: item.operation,
                toDoc: (r) {
                  final l = VehicleKhataLine.fromMap(r);
                  return {
                    'uuid': l.uuid, 'businessId': l.businessId, 'vehicleUuid': l.vehicleUuid,
                    'date': l.date.toIso8601String(), 'tafseel': l.tafseel, 'kind': l.kind.name,
                    'kharchaMinorUnits': l.kharchaMinorUnits, 'jamaMinorUnits': l.jamaMinorUnits,
                    'sourceType': l.sourceType, 'sourceId': l.sourceId,
                  };
                });
            break;
          case 'TripIncome':
            await _uploadFlat(collection: 'tripIncomes', table: TripIncome.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final i = TripIncome.fromMap(r);
                  return {
                    'uuid': i.uuid, 'businessId': i.businessId, 'tripUuid': i.tripUuid, 'customerUuid': i.customerUuid,
                    'contractUuid': i.contractUuid, 'amountMinorUnits': i.amountMinorUnits, 'description': i.description,
                    'paymentMethod': i.paymentMethod.name, 'date': i.date.toIso8601String(),
                  };
                });
            break;
          case 'Payment':
            await _uploadFlat(collection: 'paymentRecords', table: Payment.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final p = Payment.fromMap(r);
                  return {
                    'uuid': p.uuid, 'businessId': p.businessId, 'documentNumber': p.documentNumber, 'partyUuid': p.partyUuid,
                    'direction': p.direction.name, 'amountMinorUnits': p.amountMinorUnits, 'method': p.method.name,
                    'note': p.note, 'date': p.date.toIso8601String(), 'createdBy': p.createdBy,
                    'createdAt': p.createdAt.toIso8601String(),
                  };
                });
            break;
          case 'SalaryRecord':
            await _uploadFlat(collection: 'salaryRecords', table: SalaryRecord.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final s = SalaryRecord.fromMap(r);
                  return {
                    'uuid': s.uuid, 'businessId': s.businessId, 'partyUuid': s.partyUuid, 'amountMinorUnits': s.amountMinorUnits,
                    'isActive': s.isActive, 'startDate': s.startDate.toIso8601String(),
                  };
                });
            break;
          case 'SalaryPayment':
            await _uploadFlat(collection: 'salaryPayments', table: SalaryPayment.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final p = SalaryPayment.fromMap(r);
                  return {
                    'uuid': p.uuid, 'salaryRecordUuid': p.salaryRecordUuid, 'businessId': p.businessId, 'period': p.period,
                    'amountMinorUnits': p.amountMinorUnits, 'paidAt': p.paidAt.toIso8601String(),
                  };
                });
            break;
          case 'FixedAsset':
            await _uploadFlat(collection: 'fixedAssets', table: FixedAsset.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final a = FixedAsset.fromMap(r);
                  return {
                    'uuid': a.uuid, 'businessId': a.businessId, 'name': a.name, 'operatingAssetUuid': a.operatingAssetUuid,
                    'acquisitionDate': a.acquisitionDate.toIso8601String(), 'acquisitionCostMinorUnits': a.acquisitionCostMinorUnits,
                    'usefulLifeMonths': a.usefulLifeMonths, 'salvageValueMinorUnits': a.salvageValueMinorUnits, 'isActive': a.isActive,
                  };
                });
            break;
          case 'DepreciationEntry':
            await _uploadFlat(collection: 'depreciationEntries', table: DepreciationEntry.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final e = DepreciationEntry.fromMap(r);
                  return {
                    'uuid': e.uuid, 'fixedAssetUuid': e.fixedAssetUuid, 'businessId': e.businessId, 'period': e.period,
                    'amountMinorUnits': e.amountMinorUnits, 'postedAt': e.postedAt.toIso8601String(),
                  };
                });
            break;
          case 'BankAccount':
            await _uploadFlat(collection: 'bankAccounts', table: BankAccount.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final a = BankAccount.fromMap(r);
                  return {
                    'uuid': a.uuid, 'businessId': a.businessId, 'name': a.name, 'bankName': a.bankName,
                    'accountNumber': a.accountNumber, 'openingBalanceMinorUnits': a.openingBalanceMinorUnits, 'isActive': a.isActive,
                  };
                });
            break;
          case 'BankStatementLine':
            await _uploadFlat(collection: 'bankStatementLines', table: BankStatementLine.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final l = BankStatementLine.fromMap(r);
                  return {
                    'uuid': l.uuid, 'businessId': businessId, 'bankAccountUuid': l.bankAccountUuid, 'date': l.date.toIso8601String(),
                    'description': l.description, 'amountMinorUnits': l.amountMinorUnits, 'isCleared': l.isCleared,
                  };
                });
            break;
          case 'FiscalPeriod':
            await _uploadFlat(collection: 'fiscalPeriods', table: FiscalPeriod.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final p = FiscalPeriod.fromMap(r);
                  return {
                    'uuid': p.uuid, 'businessId': p.businessId, 'startDate': p.startDate.toIso8601String(),
                    'endDate': p.endDate.toIso8601String(), 'status': p.status.name,
                  };
                });
            break;
          case 'TaxRate':
            await _uploadFlat(collection: 'taxRates', table: TaxRate.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final t = TaxRate.fromMap(r);
                  return {'uuid': t.uuid, 'businessId': t.businessId, 'name': t.name, 'ratePercent': t.ratePercent, 'isActive': t.isActive};
                });
            break;
          case 'ApprovalThreshold':
            await _uploadApprovalThreshold(businessId, item);
            break;
          case 'StockMovement':
            await _uploadFlat(collection: 'stockMovements', table: StockMovement.tableName, id: item.entityId, businessId: businessId,
                toDoc: (r) {
                  final m = StockMovement.fromMap(r);
                  return {
                    'uuid': m.uuid, 'businessId': m.businessId, 'productUuid': m.productUuid, 'reason': m.reason.name,
                    'quantityChange': m.quantityChange, 'sourceType': m.sourceType, 'sourceId': m.sourceId,
                    'createdAt': m.createdAt.toIso8601String(),
                  };
                });
            break;
          case 'AuditLog':
            await _uploadAuditLog(businessId, item);
            break;
          default:
            // Other entity types aren't wired up yet — same mechanical
            // pattern as Party/Product, just not applied everywhere.
            // Skip rather than fail so it doesn't loop forever.
            continue;
        }
        await syncQueue.markSynced(item.id);
        succeeded++;
      } catch (e) {
        await syncQueue.markFailed(item.id, e.toString());
      }
    }

    return succeeded;
  }

  Future<void> _uploadJournalEntry(String businessId, SyncQueueItem item) async {
    final entry = await ledger.findByUuid(item.entityId);
    if (entry == null) return; // nothing to upload — already gone locally

    var entryNumber = entry.entryNumber;
    if (entryNumber == 0 && item.operation == SyncOperation.create) {
      entryNumber = await _claimSequenceNumber(businessId, entry.sourceType);
      await db.update(
        JournalEntry.tableName,
        {'entry_number': entryNumber},
        where: 'uuid = ?',
        whereArgs: [entry.uuid],
      );
    }

    final docData = {
      'uuid': entry.uuid,
      'businessId': entry.businessId,
      'entryNumber': entryNumber,
      'date': entry.date.toIso8601String(),
      'sourceType': entry.sourceType,
      'sourceId': entry.sourceId,
      'description': entry.description,
      'status': entry.status.name,
      'reversalOfUuid': entry.reversalOfUuid,
      'createdBy': entry.createdBy,
      'createdAt': entry.createdAt.toIso8601String(),
      'deviceId': entry.deviceId,
      'lines': entry.lines
          .map((l) => {
                'accountCode': l.accountCode,
                'debitMinorUnits': l.debitMinorUnits,
                'creditMinorUnits': l.creditMinorUnits,
                'partyUuid': l.partyUuid,
                'dimensionUuid': l.dimensionUuid,
              })
          .toList(),
    };

    await firestore
        .collection('businesses')
        .doc(businessId)
        .collection('journalEntries')
        .doc(entry.uuid)
        .set(docData);
  }

  Future<void> _uploadParty(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Party.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return; // gone locally — nothing to upload
    final party = Party.fromMap(rows.first);

    await firestore.collection('businesses').doc(businessId).collection('parties').doc(party.uuid).set({
      'uuid': party.uuid,
      'businessId': party.businessId,
      'type': party.type.name,
      'name': party.name,
      'phone': party.phone,
      'address': party.address,
      'creditLimitMinorUnits': party.creditLimitMinorUnits,
      'isActive': party.isActive,
      'updatedAt': party.updatedAt.toIso8601String(),
    });
  }

  /// Note: only `ProductRepository.create()` enqueues a sync item — every
  /// Sale/Purchase that adjusts `stockQuantity` afterward doesn't, so the
  /// synced `stockQuantity` reflects the product's state at creation, not
  /// live stock. Re-enqueueing on every stock movement is the same
  /// mechanical extension as everywhere else in this phase, just not
  /// applied yet — flagging here so the gap is visible, not silently stale.
  Future<void> _uploadProduct(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Product.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final product = Product.fromMap(rows.first);

    await firestore.collection('businesses').doc(businessId).collection('products').doc(product.uuid).set({
      'uuid': product.uuid,
      'businessId': product.businessId,
      'sku': product.sku,
      'name': product.name,
      'costPriceMinorUnits': product.costPriceMinorUnits,
      'salePriceMinorUnits': product.salePriceMinorUnits,
      'taxRatePercent': product.taxRatePercent,
      'stockQuantity': product.stockQuantity,
      'reorderLevel': product.reorderLevel,
      'isActive': product.isActive,
      'updatedAt': product.updatedAt.toIso8601String(),
    });
  }

  /// Generic upload for any entity that's a single flat row keyed by its
  /// own `uuid` (no child line rows to embed) — every simple registry
  /// table (Category, OperatingAsset, Trip, FishCategory, Contract, ...)
  /// shares this exact shape, so only the table/collection names and the
  /// row->doc field mapping actually differ per entity; see each call
  /// site in [uploadPending]'s switch.
  Future<void> _uploadFlat({
    required String collection,
    required String table,
    required String id,
    required String businessId,
    required Map<String, Object?> Function(Map<String, Object?> row) toDoc,
    SyncOperation operation = SyncOperation.create,
  }) async {
    if (operation == SyncOperation.delete) {
      await firestore.collection('businesses').doc(businessId).collection(collection).doc(id).delete();
      return;
    }
    final rows = await db.query(table, where: 'uuid = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    await firestore.collection('businesses').doc(businessId).collection(collection).doc(id).set(toDoc(rows.first));
  }

  /// ApprovalThreshold has no `uuid` (its primary key is the composite
  /// `(business_id, transaction_type)`) — entityId is the synthetic
  /// `businessId:transactionType` key ApprovalThresholdRepository.
  /// setThreshold() enqueues, parsed back apart here.
  Future<void> _uploadApprovalThreshold(String businessId, SyncQueueItem item) async {
    final transactionType = item.entityId.split(':').last;
    final rows = await db.query(
      ApprovalThreshold.tableName,
      where: 'business_id = ? AND transaction_type = ?',
      whereArgs: [businessId, transactionType],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final threshold = ApprovalThreshold.fromMap(rows.first);
    await firestore.collection('businesses').doc(businessId).collection('approvalThresholds').doc(transactionType).set({
      'businessId': threshold.businessId,
      'transactionType': threshold.transactionType,
      'thresholdMinorUnits': threshold.thresholdMinorUnits,
    });
  }

  /// AuditLog's primary key is `id`, not `uuid` like everything else
  /// [_uploadFlat] handles — bespoke method rather than generalizing
  /// [_uploadFlat] to a configurable id-column name for one outlier.
  Future<void> _uploadAuditLog(String businessId, SyncQueueItem item) async {
    final rows = await db.query(AuditLog.tableName, where: 'id = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final log = AuditLog.fromMap(rows.first);
    await firestore.collection('businesses').doc(businessId).collection('auditLogs').doc(log.id).set({
      'id': log.id,
      'businessId': log.businessId,
      'action': log.action,
      'entityType': log.entityType,
      'entityId': log.entityId,
      'performedBy': log.performedBy,
      'performedAt': log.performedAt.toIso8601String(),
      'details': log.details,
    });
  }

  /// Writes the Business's own profile fields directly onto
  /// `businesses/{businessId}` — the same document every other entity's
  /// subcollections (parties, products, journalEntries, ...) already
  /// hang off, just the parent doc's own fields rather than a
  /// subcollection. `firestore.rules` only allows a Super Admin to write
  /// here directly (`match /businesses/{businessId} { allow write: if
  /// isSuperAdmin(); }`), which matches who's ever allowed to create a
  /// business in the first place (BusinessSwitcherScreen's "+" only
  /// shows for a Super Admin) — see [restoreFromCloud] for the read side
  /// this exists to support.
  Future<void> _uploadBusiness(SyncQueueItem item) async {
    final rows = await db.query(Business.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final business = Business.fromMap(rows.first);

    await firestore.collection('businesses').doc(business.uuid).set({
      'uuid': business.uuid,
      'name': business.name,
      'type': business.type.name,
      'baseCurrency': business.baseCurrency,
      'address': business.address,
      'phone': business.phone,
      'isActive': business.isActive,
      'createdAt': business.createdAt.toIso8601String(),
      'updatedAt': business.updatedAt.toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> _uploadPurchase(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Purchase.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final lineRows = await db.query(PurchaseLine.tableName, where: 'purchase_uuid = ?', whereArgs: [item.entityId]);
    final purchase = Purchase.fromMap(rows.first, lines: lineRows.map(PurchaseLine.fromMap).toList());

    await firestore.collection('businesses').doc(businessId).collection('purchases').doc(purchase.uuid).set({
      'uuid': purchase.uuid,
      'businessId': purchase.businessId,
      'documentNumber': purchase.documentNumber,
      'supplierUuid': purchase.supplierUuid,
      'date': purchase.date.toIso8601String(),
      'status': purchase.status.name,
      'createdBy': purchase.createdBy,
      'createdAt': purchase.createdAt.toIso8601String(),
      'lines': purchase.lines
          .map((l) => {
                'productUuid': l.productUuid,
                'quantity': l.quantity,
                'unitCostMinorUnits': l.unitCostMinorUnits,
                'taxRatePercent': l.taxRatePercent,
              })
          .toList(),
    });
  }

  Future<void> _uploadSale(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Sale.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final lineRows = await db.query(SaleLine.tableName, where: 'sale_uuid = ?', whereArgs: [item.entityId]);
    final sale = Sale.fromMap(rows.first, lines: lineRows.map(SaleLine.fromMap).toList());

    await firestore.collection('businesses').doc(businessId).collection('sales').doc(sale.uuid).set({
      'uuid': sale.uuid,
      'businessId': sale.businessId,
      'documentNumber': sale.documentNumber,
      'customerUuid': sale.customerUuid,
      'paymentMethod': sale.paymentMethod.name,
      'date': sale.date.toIso8601String(),
      'status': sale.status.name,
      'createdBy': sale.createdBy,
      'createdAt': sale.createdAt.toIso8601String(),
      'discountMinorUnits': sale.discountMinorUnits,
      'lines': sale.lines
          .map((l) => {
                // [id] is round-tripped (not just productUuid/quantity)
                // so a restored RefundLine's saleLineId — an autoincrement
                // id, not a uuid — still points at the right line after
                // _downloadSales recreates it; see that method.
                'id': l.id,
                'productUuid': l.productUuid,
                'quantity': l.quantity,
                'unitPriceMinorUnits': l.unitPriceMinorUnits,
                'unitCostMinorUnits': l.unitCostMinorUnits,
                'taxRatePercent': l.taxRatePercent,
              })
          .toList(),
    });
  }

  Future<void> _uploadRefund(String businessId, SyncQueueItem item) async {
    final rows = await db.query(Refund.tableName, where: 'uuid = ?', whereArgs: [item.entityId], limit: 1);
    if (rows.isEmpty) return;
    final lineRows = await db.query(RefundLine.tableName, where: 'refund_uuid = ?', whereArgs: [item.entityId]);
    final refund = Refund.fromMap(rows.first, lines: lineRows.map(RefundLine.fromMap).toList());

    await firestore.collection('businesses').doc(businessId).collection('refunds').doc(refund.uuid).set({
      'uuid': refund.uuid,
      'businessId': refund.businessId,
      'saleUuid': refund.saleUuid,
      'documentNumber': refund.documentNumber,
      'date': refund.date.toIso8601String(),
      'reason': refund.reason,
      'createdBy': refund.createdBy,
      'createdAt': refund.createdAt.toIso8601String(),
      'discountMinorUnits': refund.discountMinorUnits,
      'lines': refund.lines
          .map((l) => {
                'saleLineId': l.saleLineId,
                'productUuid': l.productUuid,
                'quantity': l.quantity,
                'unitPriceMinorUnits': l.unitPriceMinorUnits,
                'unitCostMinorUnits': l.unitCostMinorUnits,
                'taxRatePercent': l.taxRatePercent,
              })
          .toList(),
    });
  }

  /// Atomic counter via a Firestore client-side transaction — the free-
  /// plan substitute for a Cloud Function issuing sequence numbers. See
  /// PHASES.md Section 14 ("gapless sequential invoice numbers") and the
  /// header note on this class.
  Future<int> _claimSequenceNumber(String businessId, String docType) {
    final ref = firestore
        .collection('businesses')
        .doc(businessId)
        .collection('numberSequences')
        .doc(docType);

    return firestore.runTransaction<int>((txn) async {
      final snapshot = await txn.get(ref);
      final next = ((snapshot.data()?['lastNumber'] as int?) ?? 0) + 1;
      txn.set(ref, {'lastNumber': next});
      return next;
    });
  }

  /// **Scope note:** this only syncs the ledger (JournalEntry + lines),
  /// the same scope as [uploadPending]. It does *not* pull the domain
  /// records that caused those entries (a remote Sale, its
  /// StockMovement, the resulting Product.stockQuantity change) — those
  /// still need their own sync wiring (see PHASES.md Phase 5 "Sync for
  /// entities other than JournalEntry"). Downloading a remote device's
  /// Sale today merges its accounting effect (balances, P&L, ledgers all
  /// read live off journal_lines) but not its inventory effect locally.
  ///
  /// Pulls every JournalEntry for [businessId] from Firestore and merges
  /// it into local SQL:
  /// - Not present locally (another device created it) -> insert it and
  ///   its lines.
  /// - Present with the same status -> nothing to do.
  /// - Present locally as `posted` but remote is `reversed`/`void_` ->
  ///   we haven't independently transitioned it, so it's safe to just
  ///   adopt the remote status.
  /// - Present locally as `reversed`/`void_` while remote is still
  ///   `posted` -> our transition hasn't reached the server yet; the next
  ///   [uploadPending] call will push it. Nothing to do here.
  /// - Present locally as one terminal status while remote independently
  ///   became a *different* terminal status (e.g. local voided it, a
  ///   second device reversed it) -> a genuine conflict. Recorded via
  ///   [ConflictRecordRepository] for manual resolution; local is left
  ///   untouched rather than guessing which side is "right."
  ///
  /// Fetches the whole collection every call rather than tracking a
  /// cursor — fine at today's scale, a rollup-style optimization for
  /// later if a business's journalEntries collection gets large (see
  /// PHASES.md Section 12's rollup-table note, same idea applied here).
  Future<DownloadResult> downloadAndMerge(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('journalEntries').get();

    var inserted = 0;
    var statusUpdated = 0;
    var conflicts = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uuid = data['uuid'] as String;
      final remoteStatus = data['status'] as String;

      final localRows = await db.query(JournalEntry.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);

      if (localRows.isEmpty) {
        await _insertRemoteEntry(data);
        inserted++;
        continue;
      }

      final localStatus = localRows.first['status'] as String;
      if (localStatus == remoteStatus) continue;

      if (localStatus == JournalEntryStatus.posted.name) {
        await db.update(JournalEntry.tableName, {'status': remoteStatus}, where: 'uuid = ?', whereArgs: [uuid]);
        statusUpdated++;
      } else if (remoteStatus != JournalEntryStatus.posted.name) {
        await conflictRecords.record(
          businessId: businessId,
          entityType: 'JournalEntry',
          entityId: uuid,
          conflictingFields: ['status'],
        );
        conflicts++;
      }
      // else: remoteStatus == posted but local already transitioned —
      // our transition just hasn't uploaded yet.
    }

    return DownloadResult(inserted: inserted, statusUpdated: statusUpdated, conflicts: conflicts);
  }

  Future<void> _insertRemoteEntry(Map<String, Object?> data) async {
    final uuid = data['uuid'] as String;

    await db.transaction((txn) async {
      await txn.insert(
        JournalEntry.tableName,
        {
          'uuid': uuid,
          'business_id': data['businessId'],
          'entry_number': data['entryNumber'],
          'date': data['date'],
          'source_type': data['sourceType'],
          'source_id': data['sourceId'],
          'description': data['description'],
          'status': data['status'],
          'reversal_of_uuid': data['reversalOfUuid'],
          'created_by': data['createdBy'],
          'created_at': data['createdAt'],
          'device_id': data['deviceId'],
          'sync_status': SyncStatus.synced.name,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final lines = (data['lines'] as List?) ?? [];
      for (final rawLine in lines) {
        final line = rawLine as Map<Object?, Object?>;
        await txn.insert(
          JournalLine.tableName,
          {
            'entry_uuid': uuid,
            'account_code': line['accountCode'],
            'debit_minor_units': line['debitMinorUnits'],
            'credit_minor_units': line['creditMinorUnits'],
            'party_uuid': line['partyUuid'],
            'dimension_uuid': line['dimensionUuid'],
          },
        );
      }
    });
  }

  /// Recovers a signed-in user's data after local storage has been wiped
  /// — the normal case on web, where `sqflite_common_ffi_web` persists to
  /// IndexedDB in an experimental, occasionally lossy way (see its own
  /// README: "experimental... slow... bugs"), so a closed-and-reopened
  /// browser tab can come back with an empty database even though
  /// nothing was deliberately deleted. Called once, from
  /// `currentBusinessIdProvider`, only when local SQLite has *zero*
  /// Business rows — never on a normal boot with data already present.
  ///
  /// [isSuperAdmin]/[businessAccess] decide which businessIds to look
  /// for: every business in Firestore for a Super Admin (their own
  /// `/businesses/{id}` read rule passes for any id), or just the ones in
  /// their own profile's `businessAccess` map for staff. For each
  /// recoverable id: re-creates the local `Business` row (+ re-seeds its
  /// Chart of Accounts) from the profile fields [_uploadBusiness] wrote,
  /// then pulls back its Parties/Products/Purchases/Sales/Refunds and
  /// finally its JournalEntries (via the existing [downloadAndMerge]) —
  /// in that order, since journal entries reference the others by uuid.
  ///
  /// **Known gap, same shape as [downloadAndMerge]'s scope note:**
  /// Category/Brand records and the StockMovement audit trail aren't
  /// synced at all yet, so a restored Product can be missing its
  /// category label and a restored business's stock-movement history
  /// starts blank — the stock *quantity* itself is correct (Product is
  /// fully restored), just not the move-by-move trail that built it.
  /// Only a business created *after* this restore path shipped has a
  /// `/businesses/{id}` profile doc to recover from at all; one created
  /// before it has no such doc and can't be recovered this way.
  Future<bool> restoreFromCloud({
    required bool isSuperAdmin,
    required Map<String, String> businessAccess,
  }) async {
    List<String> businessIds;
    if (isSuperAdmin) {
      final snapshot = await firestore.collection('businesses').get();
      businessIds = snapshot.docs.map((d) => d.id).toList();
    } else {
      businessIds = businessAccess.keys.toList();
    }
    if (businessIds.isEmpty) return false;

    var restoredAny = false;
    for (final businessId in businessIds) {
      final doc = await firestore.collection('businesses').doc(businessId).get();
      final data = doc.data();
      if (data == null || data['name'] == null) {
        // No profile doc (predates this restore path, or was never
        // uploaded) — nothing to recreate the Business shell from, so
        // there's nowhere for its domain data to attach to locally either.
        continue;
      }

      await db.insert(
        Business.tableName,
        {
          'uuid': businessId,
          'name': data['name'],
          'type': data['type'],
          'base_currency': data['baseCurrency'],
          'address': data['address'],
          'phone': data['phone'],
          'is_active': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'created_at': data['createdAt'],
          'updated_at': data['updatedAt'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await seedChartOfAccounts(db, businessId);
      restoredAny = true;

      await _downloadParties(businessId);
      await _downloadProducts(businessId);
      await _downloadFlat(collection: 'categories', table: Category.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'name': d['name'], 'is_active': _boolToInt(d['isActive']),
          });
      await _downloadFlat(collection: 'brands', table: Brand.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'name': d['name'], 'is_active': _boolToInt(d['isActive']),
          });
      await _downloadFlat(collection: 'operatingAssets', table: OperatingAsset.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'type': d['type'], 'name': d['name'],
            'registration_number': d['registrationNumber'], 'is_active': _boolToInt(d['isActive']),
          });
      await _downloadFlat(collection: 'trips', table: Trip.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'trip_type': d['tripType'], 'asset_uuid': d['assetUuid'],
            'captain_uuid': d['captainUuid'], 'status': d['status'], 'start_date': d['startDate'],
            'end_date': d['endDate'], 'notes': d['notes'],
          });
      await _downloadFlat(collection: 'tripExpenses', table: TripExpense.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'trip_uuid': d['tripUuid'], 'asset_uuid': d['assetUuid'], 'business_id': d['businessId'],
            'category': d['category'], 'amount_minor_units': d['amountMinorUnits'], 'description': d['description'],
            'date': d['date'],
          });
      await _downloadFlat(collection: 'fishCategories', table: FishCategory.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'name': d['name'], 'is_active': _boolToInt(d['isActive']),
          });
      await _downloadFlat(collection: 'catchEntries', table: CatchEntry.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'trip_uuid': d['tripUuid'], 'business_id': d['businessId'],
            'fish_category_uuid': d['fishCategoryUuid'], 'weight_kg': d['weightKg'],
            'estimated_value_minor_units': d['estimatedValueMinorUnits'],
          });
      await _downloadFlat(collection: 'fishSales', table: FishSale.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'trip_uuid': d['tripUuid'], 'customer_uuid': d['customerUuid'],
            'fish_category_uuid': d['fishCategoryUuid'], 'weight_kg': d['weightKg'],
            'unit_price_minor_units_per_kg': d['unitPriceMinorUnitsPerKg'], 'payment_method': d['paymentMethod'], 'date': d['date'],
          });
      await _downloadFlat(collection: 'contracts', table: Contract.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'customer_uuid': d['customerUuid'], 'description': d['description'],
            'rate_per_trip_minor_units': d['ratePerTripMinorUnits'], 'rate_per_ton_minor_units': d['ratePerTonMinorUnits'],
            'is_active': _boolToInt(d['isActive']), 'start_date': d['startDate'], 'end_date': d['endDate'],
          });
      await _downloadFlat(collection: 'monthlySettlements', table: MonthlySettlement.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'company_uuid': d['companyUuid'], 'year': d['year'],
            'month': d['month'], 'rate_per_ton_minor_units': d['ratePerTonMinorUnits'],
            'total_weight_kg': d['totalWeightKg'] ?? ((d['totalWeightTons'] as num?) ?? 0) * 1000,
            'amount_minor_units': d['amountMinorUnits'], 'date': d['date'],
          });
      await _downloadFlat(collection: 'weightEntries', table: WeightEntry.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'vehicle_uuid': d['vehicleUuid'], 'company_uuid': d['companyUuid'],
            'date': d['date'], 'weight_kg': d['weightKg'] ?? ((d['weightTons'] as num?) ?? 0) * 1000,
            'notes': d['notes'], 'settlement_uuid': d['settlementUuid'], 'amount_minor_units': d['amountMinorUnits'],
          });
      await _downloadFlat(collection: 'vehicleKhataLines', table: VehicleKhataLine.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'vehicle_uuid': d['vehicleUuid'], 'date': d['date'],
            'tafseel': d['tafseel'], 'kind': d['kind'], 'kharcha_minor_units': d['kharchaMinorUnits'],
            'jama_minor_units': d['jamaMinorUnits'], 'source_type': d['sourceType'], 'source_id': d['sourceId'],
          });
      await _downloadFlat(collection: 'tripIncomes', table: TripIncome.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'trip_uuid': d['tripUuid'], 'customer_uuid': d['customerUuid'],
            'contract_uuid': d['contractUuid'], 'amount_minor_units': d['amountMinorUnits'], 'description': d['description'],
            'payment_method': d['paymentMethod'], 'date': d['date'],
          });
      await _downloadFlat(collection: 'paymentRecords', table: Payment.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'document_number': d['documentNumber'], 'party_uuid': d['partyUuid'],
            'direction': d['direction'], 'amount_minor_units': d['amountMinorUnits'], 'method': d['method'], 'note': d['note'],
            'date': d['date'], 'created_by': d['createdBy'], 'created_at': d['createdAt'],
          });
      await _downloadFlat(collection: 'salaryRecords', table: SalaryRecord.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'party_uuid': d['partyUuid'],
            'amount_minor_units': d['amountMinorUnits'], 'is_active': _boolToInt(d['isActive']), 'start_date': d['startDate'],
          });
      await _downloadFlat(collection: 'salaryPayments', table: SalaryPayment.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'salary_record_uuid': d['salaryRecordUuid'], 'business_id': d['businessId'], 'period': d['period'],
            'amount_minor_units': d['amountMinorUnits'], 'paid_at': d['paidAt'],
          });
      await _downloadFlat(collection: 'fixedAssets', table: FixedAsset.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'name': d['name'], 'operating_asset_uuid': d['operatingAssetUuid'],
            'acquisition_date': d['acquisitionDate'], 'acquisition_cost_minor_units': d['acquisitionCostMinorUnits'],
            'useful_life_months': d['usefulLifeMonths'], 'salvage_value_minor_units': d['salvageValueMinorUnits'],
            'is_active': _boolToInt(d['isActive']),
          });
      await _downloadFlat(collection: 'depreciationEntries', table: DepreciationEntry.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'fixed_asset_uuid': d['fixedAssetUuid'], 'business_id': d['businessId'], 'period': d['period'],
            'amount_minor_units': d['amountMinorUnits'], 'posted_at': d['postedAt'],
          });
      await _downloadFlat(collection: 'bankAccounts', table: BankAccount.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'name': d['name'], 'bank_name': d['bankName'],
            'account_number': d['accountNumber'], 'opening_balance_minor_units': d['openingBalanceMinorUnits'],
            'is_active': _boolToInt(d['isActive']),
          });
      await _downloadFlat(collection: 'bankStatementLines', table: BankStatementLine.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'bank_account_uuid': d['bankAccountUuid'], 'date': d['date'], 'description': d['description'],
            'amount_minor_units': d['amountMinorUnits'], 'is_cleared': _boolToInt(d['isCleared']),
          });
      await _downloadFlat(collection: 'fiscalPeriods', table: FiscalPeriod.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'start_date': d['startDate'], 'end_date': d['endDate'],
            'status': d['status'],
          });
      await _downloadFlat(collection: 'taxRates', table: TaxRate.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'name': d['name'], 'rate_percent': d['ratePercent'],
            'is_active': _boolToInt(d['isActive']),
          });
      await _downloadApprovalThresholds(businessId);
      await _downloadFlat(collection: 'stockMovements', table: StockMovement.tableName, businessId: businessId, toRow: (d) => {
            'uuid': d['uuid'], 'business_id': d['businessId'], 'product_uuid': d['productUuid'], 'reason': d['reason'],
            'quantity_change': d['quantityChange'], 'source_type': d['sourceType'], 'source_id': d['sourceId'],
            'created_at': d['createdAt'],
          });
      await _downloadAuditLogs(businessId);
      await _downloadPurchases(businessId);
      await _downloadSales(businessId);
      await _downloadRefunds(businessId);
      await downloadAndMerge(businessId);
      if (numbering != null) await numbering!.resyncFromIssuedNumbers(businessId);
    }

    return restoredAny;
  }

  static int _boolToInt(Object? value) => (value as bool? ?? true) ? 1 : 0;

  /// Generic download for any [_uploadFlat]-shaped entity: every doc
  /// under `businesses/{businessId}/{collection}` gets upserted into
  /// [table] via [toRow]'s field mapping (insert-if-missing, same
  /// `ConflictAlgorithm.ignore` idempotency as every other restore path
  /// here — re-running restoreFromCloud is always safe).
  Future<void> _downloadFlat({
    required String collection,
    required String table,
    required String businessId,
    required Map<String, Object?> Function(Map<String, Object?> data) toRow,
  }) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection(collection).get();
    for (final doc in snapshot.docs) {
      await db.insert(table, toRow(doc.data()), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _downloadAuditLogs(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('auditLogs').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      await db.insert(
        AuditLog.tableName,
        {
          'id': data['id'],
          'business_id': data['businessId'],
          'action': data['action'],
          'entity_type': data['entityType'],
          'entity_id': data['entityId'],
          'performed_by': data['performedBy'],
          'performed_at': data['performedAt'],
          'details': data['details'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _downloadApprovalThresholds(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('approvalThresholds').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      await db.insert(
        ApprovalThreshold.tableName,
        {
          'business_id': data['businessId'],
          'transaction_type': data['transactionType'],
          'threshold_minor_units': data['thresholdMinorUnits'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _downloadParties(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('parties').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      await db.insert(
        Party.tableName,
        {
          'uuid': data['uuid'],
          'business_id': data['businessId'],
          'type': data['type'],
          'name': data['name'],
          'phone': data['phone'],
          'address': data['address'],
          'credit_limit_minor_units': data['creditLimitMinorUnits'],
          'is_active': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'updated_at': data['updatedAt'],
          'created_at': data['updatedAt'], // not separately uploaded — see _uploadParty
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _downloadProducts(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('products').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      await db.insert(
        Product.tableName,
        {
          'uuid': data['uuid'],
          'business_id': data['businessId'],
          'sku': data['sku'],
          'name': data['name'],
          'cost_price_minor_units': data['costPriceMinorUnits'],
          'sale_price_minor_units': data['salePriceMinorUnits'],
          'tax_rate_percent': data['taxRatePercent'],
          'stock_quantity': data['stockQuantity'],
          'reorder_level': data['reorderLevel'],
          'is_active': (data['isActive'] as bool? ?? true) ? 1 : 0,
          'updated_at': data['updatedAt'],
          'created_at': data['updatedAt'], // not separately uploaded — see _uploadProduct
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _downloadPurchases(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('purchases').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uuid = data['uuid'] as String;
      await db.transaction((txn) async {
        await txn.insert(
          Purchase.tableName,
          {
            'uuid': uuid,
            'business_id': data['businessId'],
            'document_number': data['documentNumber'],
            'supplier_uuid': data['supplierUuid'],
            'date': data['date'],
            'status': data['status'],
            'created_by': data['createdBy'],
            'created_at': data['createdAt'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final lines = (data['lines'] as List?) ?? [];
        for (final rawLine in lines) {
          final line = rawLine as Map<Object?, Object?>;
          await txn.insert(PurchaseLine.tableName, {
            'purchase_uuid': uuid,
            'product_uuid': line['productUuid'],
            'quantity': line['quantity'],
            'unit_cost_minor_units': line['unitCostMinorUnits'],
            'tax_rate_percent': line['taxRatePercent'],
          });
        }
      });
    }
  }

  Future<void> _downloadSales(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('sales').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uuid = data['uuid'] as String;
      await db.transaction((txn) async {
        await txn.insert(
          Sale.tableName,
          {
            'uuid': uuid,
            'business_id': data['businessId'],
            'document_number': data['documentNumber'],
            'customer_uuid': data['customerUuid'],
            'payment_method': data['paymentMethod'],
            'date': data['date'],
            'status': data['status'],
            'created_by': data['createdBy'],
            'created_at': data['createdAt'],
            'discount_minor_units': data['discountMinorUnits'] ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final lines = (data['lines'] as List?) ?? [];
        for (final rawLine in lines) {
          final line = rawLine as Map<Object?, Object?>;
          await txn.insert(
            SaleLine.tableName,
            {
              // Explicit id, not autoincrement-assigned — RefundLine.
              // saleLineId (restored by _downloadRefunds) references
              // this exact id, carried over from the original device via
              // _uploadSale, so it must survive the round-trip unchanged.
              'id': line['id'],
              'sale_uuid': uuid,
              'product_uuid': line['productUuid'],
              'quantity': line['quantity'],
              'unit_price_minor_units': line['unitPriceMinorUnits'],
              'unit_cost_minor_units': line['unitCostMinorUnits'],
              'tax_rate_percent': line['taxRatePercent'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });
    }
  }

  Future<void> _downloadRefunds(String businessId) async {
    final snapshot = await firestore.collection('businesses').doc(businessId).collection('refunds').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uuid = data['uuid'] as String;
      await db.transaction((txn) async {
        await txn.insert(
          Refund.tableName,
          {
            'uuid': uuid,
            'business_id': data['businessId'],
            'sale_uuid': data['saleUuid'],
            'document_number': data['documentNumber'],
            'date': data['date'],
            'reason': data['reason'],
            'created_by': data['createdBy'],
            'created_at': data['createdAt'],
            'discount_minor_units': data['discountMinorUnits'] ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final lines = (data['lines'] as List?) ?? [];
        for (final rawLine in lines) {
          final line = rawLine as Map<Object?, Object?>;
          await txn.insert(RefundLine.tableName, {
            'refund_uuid': uuid,
            'sale_line_id': line['saleLineId'],
            'product_uuid': line['productUuid'],
            'quantity': line['quantity'],
            'unit_price_minor_units': line['unitPriceMinorUnits'],
            'unit_cost_minor_units': line['unitCostMinorUnits'],
            'tax_rate_percent': line['taxRatePercent'],
          });
        }
      });
    }
  }

  /// Protects data that's already sitting in local SQLite but was never
  /// enqueued for upload — the case for every business/Sale/Product/etc.
  /// created *before* sync coverage existed for its entity type (this
  /// restore system itself shipped well after Phase 1's Sale/Product, for
  /// instance). Without this, that pre-existing data has no Firestore
  /// backup at all and [restoreFromCloud] would have nothing to recover
  /// it from if local storage is ever wiped — exactly the gap a business
  /// created "before today's fix" sits in. Scans every synced entity
  /// table for rows with no matching `sync_queue_items` row at all (not
  /// "pending" — *no row, ever*) and enqueues them now. Idempotent: a
  /// row enqueued (and eventually synced) by a previous call is never
  /// re-enqueued, so this is safe to run on every `syncAll()` — see
  /// [_backfilledThisSession] for why it still only actually scans once
  /// per session rather than on every call.
  Future<int> backfillSyncQueue(String businessId) async {
    var enqueued = 0;
    enqueued += await _backfillBusinessRow(businessId);

    const simpleTables = <(String table, String entityType)>[
      (Party.tableName, 'Party'),
      (Product.tableName, 'Product'),
      (Category.tableName, 'Category'),
      (Brand.tableName, 'Brand'),
      (OperatingAsset.tableName, 'OperatingAsset'),
      (Trip.tableName, 'Trip'),
      (TripExpense.tableName, 'TripExpense'),
      (FishCategory.tableName, 'FishCategory'),
      (CatchEntry.tableName, 'CatchEntry'),
      (FishSale.tableName, 'FishSale'),
      (Contract.tableName, 'Contract'),
      (TripIncome.tableName, 'TripIncome'),
      (WeightEntry.tableName, 'WeightEntry'),
      (MonthlySettlement.tableName, 'MonthlySettlement'),
      (VehicleKhataLine.tableName, 'VehicleKhataLine'),
      (Payment.tableName, 'Payment'),
      (SalaryRecord.tableName, 'SalaryRecord'),
      (SalaryPayment.tableName, 'SalaryPayment'),
      (FixedAsset.tableName, 'FixedAsset'),
      (DepreciationEntry.tableName, 'DepreciationEntry'),
      (BankAccount.tableName, 'BankAccount'),
      (FiscalPeriod.tableName, 'FiscalPeriod'),
      (TaxRate.tableName, 'TaxRate'),
      (Purchase.tableName, 'Purchase'),
      (Sale.tableName, 'Sale'),
      (Refund.tableName, 'Refund'),
      (StockMovement.tableName, 'StockMovement'),
    ];
    for (final (table, entityType) in simpleTables) {
      enqueued += await _backfillTable(table: table, entityType: entityType, businessId: businessId);
    }

    enqueued += await _backfillTable(table: AuditLog.tableName, entityType: 'AuditLog', businessId: businessId, idColumn: 'id');
    enqueued += await _backfillBankStatementLines(businessId);
    enqueued += await _backfillApprovalThresholds(businessId);
    return enqueued;
  }

  /// The Business row itself has no `business_id` column (its own
  /// `uuid` *is* the business id) — special-cased rather than folded
  /// into [_backfillTable]'s generic `WHERE business_id = ?` shape.
  Future<int> _backfillBusinessRow(String businessId) async {
    final rows = await db.query(Business.tableName, where: 'uuid = ?', whereArgs: [businessId], limit: 1);
    if (rows.isEmpty) return 0;
    final alreadyTracked = await db.query(
      SyncQueueItem.tableName,
      where: 'business_id = ? AND entity_type = ? AND entity_id = ?',
      whereArgs: [businessId, 'Business', businessId],
      limit: 1,
    );
    if (alreadyTracked.isNotEmpty) return 0;
    await syncQueue.enqueue(db, businessId: businessId, entityType: 'Business', entityId: businessId, operation: SyncOperation.create);
    return 1;
  }

  /// Every row in [table] for [businessId] with no `sync_queue_items` row
  /// at all yet (regardless of that row's status — pending/failed rows
  /// are still "already tracked," just not yet uploaded; this is only
  /// for rows that predate sync coverage existing for this entity type).
  Future<int> _backfillTable({
    required String table,
    required String entityType,
    required String businessId,
    String idColumn = 'uuid',
  }) async {
    final rows = await db.rawQuery('''
      SELECT t.$idColumn AS id FROM $table t
      WHERE t.business_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM ${SyncQueueItem.tableName} q
          WHERE q.business_id = ? AND q.entity_type = ? AND q.entity_id = t.$idColumn
        )
    ''', [businessId, businessId, entityType]);

    for (final row in rows) {
      await syncQueue.enqueue(
        db,
        businessId: businessId,
        entityType: entityType,
        entityId: row['id'] as String,
        operation: SyncOperation.create,
      );
    }
    return rows.length;
  }

  /// BankStatementLine has no `business_id` column of its own (see
  /// _uploadBankStatementLine's note) — joins through bank_accounts to
  /// scope the scan, same reasoning as that upload method.
  Future<int> _backfillBankStatementLines(String businessId) async {
    final rows = await db.rawQuery('''
      SELECT l.uuid AS id FROM ${BankStatementLine.tableName} l
      INNER JOIN ${BankAccount.tableName} a ON a.uuid = l.bank_account_uuid
      WHERE a.business_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM ${SyncQueueItem.tableName} q
          WHERE q.business_id = ? AND q.entity_type = 'BankStatementLine' AND q.entity_id = l.uuid
        )
    ''', [businessId, businessId]);

    for (final row in rows) {
      await syncQueue.enqueue(
        db,
        businessId: businessId,
        entityType: 'BankStatementLine',
        entityId: row['id'] as String,
        operation: SyncOperation.create,
      );
    }
    return rows.length;
  }

  /// ApprovalThreshold has no `uuid` — same synthetic
  /// `businessId:transactionType` entityId as [_uploadApprovalThreshold].
  Future<int> _backfillApprovalThresholds(String businessId) async {
    final rows = await db.query(ApprovalThreshold.tableName, where: 'business_id = ?', whereArgs: [businessId]);
    var enqueued = 0;
    for (final row in rows) {
      final transactionType = row['transaction_type'] as String;
      final entityId = '$businessId:$transactionType';
      final alreadyTracked = await db.query(
        SyncQueueItem.tableName,
        where: 'business_id = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [businessId, 'ApprovalThreshold', entityId],
        limit: 1,
      );
      if (alreadyTracked.isNotEmpty) continue;
      await syncQueue.enqueue(db, businessId: businessId, entityType: 'ApprovalThreshold', entityId: entityId, operation: SyncOperation.create);
      enqueued++;
    }
    return enqueued;
  }
}
