import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/accounting/journal_entry.dart';
import '../../../core/accounting/ledger_repository.dart';
import '../../../core/sync/sync_queue_item.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../../core/system/audit_log_repository.dart';
import '../../../core/system/number_sequence_service.dart';
import '../inventory/product.dart';
import '../inventory/product_repository.dart';
import 'purchase.dart';

const _uuid = Uuid();

class PurchaseLineInput {
  PurchaseLineInput({required this.productUuid, required this.quantity, required this.unitCostMinorUnits});
  final String productUuid;
  final int quantity;
  final int unitCostMinorUnits;
}

/// Credit purchase from a supplier: stock increases, supplier payable
/// increases. Posts Dr Inventory(1040) [+ Dr Tax Payable(2020) for input
/// tax, if the product carries a tax rate] / Cr Accounts Payable(2010) for
/// the tax-inclusive total, tagged to the supplier so it shows up in their
/// ledger (PartyRepository.outstandingBalanceMinorUnits). See PHASES.md
/// Section 11.
///
/// Netting input tax straight through account 2020 (rather than a
/// separate "Tax Receivable" account) is a deliberate Phase 2
/// simplification: it gives a correct net VAT/sales-tax position in one
/// control account, which is enough for a small business's own books, but
/// is not a substitute for proper input/output tax reporting if a real
/// tax filing needs that breakdown — that's future Tax Summary report
/// work, not a Phase 2 goal.
class PurchaseRepository {
  PurchaseRepository(this.db, this.ledger, this.products, this.numbering, [this.auditLog, this.syncQueue]);

  final Database db;
  final LedgerRepository ledger;
  final ProductRepository products;
  final NumberSequenceService numbering;
  final AuditLogRepository? auditLog;

  /// Optional, opt-in — see FirestoreSyncService.restoreFromCloud() for
  /// why a Purchase enqueues itself the same way Party/Product do.
  final SyncQueueRepository? syncQueue;

  Future<Purchase> create({
    required String businessId,
    required String supplierUuid,
    required String createdBy,
    required String deviceId,
    required List<PurchaseLineInput> lineInputs,
    DateTime? date,
  }) async {
    if (lineInputs.isEmpty) {
      throw ArgumentError('A purchase must have at least one line');
    }

    final documentNumber = await numbering.next(businessId: businessId, docType: DocType.purchase);
    final uuid = _uuid.v4();
    final purchaseDate = date ?? DateTime.now();

    final lines = <PurchaseLine>[];
    for (final input in lineInputs) {
      final product = await products.findByUuid(input.productUuid);
      if (product == null) {
        throw StateError('Product ${input.productUuid} not found');
      }
      lines.add(PurchaseLine(
        purchaseUuid: uuid,
        productUuid: input.productUuid,
        quantity: input.quantity,
        unitCostMinorUnits: input.unitCostMinorUnits,
        taxRatePercent: product.taxRatePercent,
      ));
    }

    final purchase = Purchase(
      uuid: uuid,
      businessId: businessId,
      documentNumber: documentNumber,
      supplierUuid: supplierUuid,
      date: purchaseDate,
      status: PurchaseStatus.posted,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      lines: lines,
    );

    final totalMinorUnits = purchase.totalMinorUnits;
    final totalTaxMinorUnits = purchase.totalTaxMinorUnits;
    final grandTotalMinorUnits = purchase.grandTotalMinorUnits;

    await db.transaction((txn) async {
      await txn.insert(Purchase.tableName, purchase.toMap());
      for (final line in lines) {
        await txn.insert(PurchaseLine.tableName, line.toMap());
      }
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: businessId,
          entityType: 'Purchase',
          entityId: uuid,
          operation: SyncOperation.create,
        );
      }

      for (final line in lineInputs) {
        await products.adjustStock(
          txn,
          businessId: businessId,
          productUuid: line.productUuid,
          quantityChange: line.quantity,
          reason: StockMovementReason.purchase,
          sourceType: 'Purchase',
          sourceId: uuid,
        );
      }

      await ledger.postWithin(
        txn,
        businessId: businessId,
        sourceType: 'Purchase',
        sourceId: uuid,
        createdBy: createdBy,
        deviceId: deviceId,
        date: purchaseDate,
        description: 'Purchase $documentNumber',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '1040', // Inventory (tax-exclusive)
            debitMinorUnits: totalMinorUnits,
            creditMinorUnits: 0,
          ),
          if (totalTaxMinorUnits > 0)
            JournalLine(
              entryUuid: '',
              accountCode: '2020', // Tax Payable — input tax claimable
              debitMinorUnits: totalTaxMinorUnits,
              creditMinorUnits: 0,
            ),
          JournalLine(
            entryUuid: '',
            accountCode: '2010', // Accounts Payable (tax-inclusive)
            debitMinorUnits: 0,
            creditMinorUnits: grandTotalMinorUnits,
            partyUuid: supplierUuid,
          ),
        ],
      );
    });

    await auditLog?.log(
      businessId: businessId,
      action: 'create',
      entityType: 'Purchase',
      entityId: purchase.uuid,
      performedBy: createdBy,
      details: '${purchase.documentNumber} — ${lines.length} line(s)',
    );

    return purchase;
  }

  Future<Purchase?> findByUuid(String uuid) async {
    final rows = await db.query(Purchase.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return null;
    final lineRows = await db.query(PurchaseLine.tableName, where: 'purchase_uuid = ?', whereArgs: [uuid]);
    return Purchase.fromMap(rows.first, lines: lineRows.map(PurchaseLine.fromMap).toList());
  }

  Future<List<Purchase>> list({required String businessId}) async {
    final rows = await db.query(
      Purchase.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'date DESC',
    );
    return rows.map(Purchase.fromMap).toList();
  }
}
