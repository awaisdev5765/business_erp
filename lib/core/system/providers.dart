import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/approval_threshold_repository.dart';
import '../accounting/balance_rollup_repository.dart';
import '../accounting/bank_account_repository.dart';
import '../accounting/chart_of_accounts_seed.dart';
import '../accounting/depreciation_service.dart';
import '../accounting/expense_repository.dart';
import '../accounting/fiscal_period_repository.dart';
import '../accounting/fixed_asset_repository.dart';
import '../accounting/ledger_repository.dart';
import '../accounting/tax_rate_repository.dart';
import '../activity/trip_expense_repository.dart';
import '../activity/trip_repository.dart';
import '../asset/operating_asset_repository.dart';
import '../identity/user_profile.dart';
import '../identity/user_profile_repository.dart';
import '../notifications/fcm_service.dart';
import '../notifications/notification_item.dart';
import '../party/party_repository.dart';
import '../sync/conflict_record_repository.dart';
import '../sync/firestore_sync_service.dart';
import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import '../tenant/business.dart';
import '../tenant/business_repository.dart';
import '../../shared/currency/currency.dart';
import '../../shared/theme/app_theme.dart';
import '../transaction/payment_repository.dart';
import '../transaction/salary_repository.dart';
import '../../features/fishery/catch_repository.dart';
import '../../features/fishery/fish_sale_repository.dart';
import '../../features/fishery/trip_profit_service.dart';
import '../../features/spare_parts/inventory/brand_repository.dart';
import '../../features/spare_parts/inventory/category_repository.dart';
import '../../features/spare_parts/inventory/product_repository.dart';
import '../../features/spare_parts/purchases/purchase_repository.dart';
import '../../features/spare_parts/sales/refund_repository.dart';
import '../../features/spare_parts/sales/sale_repository.dart';
import '../../features/transport/contract_repository.dart';
import '../../features/transport/driver_performance_service.dart';
import '../../features/transport/monthly_settlement_repository.dart';
import '../../features/transport/trip_income_repository.dart';
import '../../features/transport/vehicle_khata_repository.dart';
import '../../features/transport/vehicle_profitability_service.dart';
import '../../features/transport/weight_entry_repository.dart';
import 'audit_log_repository.dart';
import 'data_wipe_service.dart';
import 'database.dart';
import 'number_sequence_service.dart';

final databaseProvider = FutureProvider<Database>((ref) async {
  final db = await AppDatabase.open();
  return db;
});

/// User-selected active business — null means "no explicit choice yet,
/// fall back to whatever currentBusinessIdProvider's auto-seed logic
/// picks." Set by the Business Switcher (Phase 6); every screen already
/// reads the *result* via currentBusinessIdProvider, so switching just
/// means setting this and letting that provider's reactivity do the rest
/// — no screen needed to change.
final selectedBusinessIdProvider = StateProvider<String?>((ref) => null);

/// Thrown by [currentBusinessIdProvider] when the local database has no
/// Business rows at all yet — distinct from "this signed-in user has no
/// *access* to any business" (accessibleBusinessesProvider's empty
/// list), since the right UI response differs: a Super Admin should see
/// "create your first business," not "contact your administrator."
class NoBusinessExistsException implements Exception {
  @override
  String toString() => 'No business has been created yet.';
}

/// Guards [currentBusinessIdProvider]'s cloud-restore attempt to once per
/// app session — restoring is a handful of full Firestore collection
/// reads per business, not something to retry on every rebuild. Module-
/// level (not provider state) so it survives provider disposal/recreation
/// the same way the rest of this file's plain top-level constants do.
bool _cloudRestoreAttempted = false;

/// Call after a deliberate wipe so the next signed-in session can try
/// restoreFromCloud again (otherwise a stale true flag would skip it —
/// or, worse, leave wiped+restored state inconsistent).
void resetCloudRestoreAttempt() => _cloudRestoreAttempted = false;

final currentBusinessIdProvider = FutureProvider<String>((ref) async {
  final db = await ref.watch(databaseProvider.future);

  final selected = ref.watch(selectedBusinessIdProvider);
  if (selected != null) {
    final exists = await db.query(
      Business.tableName,
      where: 'uuid = ? AND is_active = 1',
      whereArgs: [selected],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      await seedChartOfAccounts(db, selected); // idempotent top-up, see seedChartOfAccounts
      return selected;
    }
    // Stale selection after wipe / deleted business — fall through.
  }

  // Auto-pick whichever business happens to be first locally — this is
  // just "which one is active by default," never a reason to *create*
  // one. Businesses are created exclusively through the Business
  // Switcher / Super Admin flow, with a name and type the Super Admin
  // actually chose (see PHASES.md's post-launch Identity work — auto-
  // seeding a generic "My Spare Parts Shop" on first sign-in was wrong:
  // it happened for *any* signed-in user, staff included, before they'd
  // even seen the app).
  final rows = await db.query(Business.tableName, where: 'is_active = 1', limit: 1);
  if (rows.isNotEmpty) {
    final businessId = rows.first['uuid'] as String;
    await seedChartOfAccounts(db, businessId);
    return businessId;
  }

  // Local SQLite has no businesses at all — on web this is the normal
  // symptom of sqflite_common_ffi_web's experimental IndexedDB backend
  // losing data across a closed/reopened tab (see FirestoreSyncService.
  // restoreFromCloud's doc comment), not necessarily a genuinely new
  // user. Try recovering from Firestore once before concluding there's
  // really nothing here yet.
  if (!_cloudRestoreAttempted) {
    _cloudRestoreAttempted = true;
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile != null) {
        final syncService = await ref.read(firestoreSyncServiceProvider.future);
        final restored = await syncService.restoreFromCloud(
          isSuperAdmin: profile.isSuperAdmin,
          businessAccess: profile.businessAccess,
        );
        if (restored) {
          final retried = await db.query(Business.tableName, where: 'is_active = 1', limit: 1);
          if (retried.isNotEmpty) {
            final businessId = retried.first['uuid'] as String;
            await seedChartOfAccounts(db, businessId);
            return businessId;
          }
        }
      }
    } catch (_) {
      // Offline or a transient Firestore error — fall through to
      // NoBusinessExistsException below, same as a genuinely new user;
      // the next app boot (online) will retry since this flag is
      // per-session, not persisted.
    }
  }

  throw NoBusinessExistsException();
});

final businessRepositoryProvider = FutureProvider<BusinessRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return BusinessRepository(db, syncQueue);
});

/// The full active [Business] record (not just its id) — lets the nav
/// shell filter destinations by `Business.type` (PHASES.md Phase 9).
final currentBusinessProvider = FutureProvider<Business>((ref) async {
  final businessId = await ref.watch(currentBusinessIdProvider.future);
  final repo = await ref.watch(businessRepositoryProvider.future);
  final business = await repo.findByUuid(businessId);
  if (business == null) {
    throw StateError('Active business $businessId not found');
  }
  return business;
});

/// The active business's currency code, defaulting to
/// [kDefaultCurrencyCode] for one that predates the field — convenience
/// wrapper so screens don't all need to unwrap currentBusinessProvider
/// just to call formatMoney().
final currentCurrencyProvider = FutureProvider<String>((ref) async {
  final business = await ref.watch(currentBusinessProvider.future);
  return business.baseCurrency ?? kDefaultCurrencyCode;
});

/// The signed-in user's email (falling back to their uid). Read fresh on
/// every call rather than cached, since sign-in/sign-out changes it.
String get currentUser =>
    FirebaseAuth.instance.currentUser?.email ?? FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

/// A stable per-device identifier would normally come from something
/// like `device_info_plus`; this stays a constant for now — true
/// multi-device differentiation matters once there are actually two
/// devices syncing the same business, which needs the rest of Phase 5's
/// download/merge half first. Tracked as a known gap, not forgotten.
const currentDeviceId = 'desktop-1';

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(FirebaseMessaging.instance, ref.watch(firestoreProvider));
});

final dataWipeServiceProvider = FutureProvider<DataWipeService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final firestore = ref.watch(firestoreProvider);
  return DataWipeService(db, firestore);
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository(ref.watch(firestoreProvider));
});

/// The signed-in user's Firestore profile (role/businessAccess/Super
/// Admin flag) — null if signed out. Used to gate Super-Admin-only UI
/// like the cross-business dashboard.
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.find(user.uid);
});

/// Every business the signed-in user may actually use: every business
/// for a Super Admin, or only the ones in their `businessAccess` map for
/// staff. Drives BusinessSwitcherScreen and AppShell's access gate — see
/// PHASES.md's post-launch Identity work ("staff log in with their own
/// assigned email, see only their business").
final accessibleBusinessesProvider = FutureProvider<List<Business>>((ref) async {
  final profile = await ref.watch(currentUserProfileProvider.future);
  final businessRepo = await ref.watch(businessRepositoryProvider.future);
  final all = await businessRepo.list();
  if (profile == null) return [];
  if (profile.isSuperAdmin) return all;
  return all.where((b) => profile.businessAccess.containsKey(b.uuid)).toList();
});

/// True if the signed-in user holds `readOnlyAuditor` on the active
/// business (and isn't the Super Admin, who always bypasses role
/// checks). The handful of screens that actually post a JournalEntry
/// (Sales, Purchases, Payroll, Fixed Assets depreciation, Approvals)
/// check this to disable their one ledger-affecting action — the rest
/// of the read-only enforcement is the nav filtering in app.dart, which
/// keeps an auditor out of those screens in the first place; this is
/// the backstop for the few financial actions that live on shared
/// screens an auditor might still reach a Save/Approve button on.
final isReadOnlyProvider = FutureProvider<bool>((ref) async {
  final profile = await ref.watch(currentUserProfileProvider.future);
  if (profile == null || profile.isSuperAdmin) return false;
  final businessId = await ref.watch(currentBusinessIdProvider.future);
  return profile.businessAccess[businessId] == 'readOnlyAuditor';
});

final firestoreSyncServiceProvider = FutureProvider<FirestoreSyncService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final firestore = ref.watch(firestoreProvider);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final conflictRecords = await ref.watch(conflictRecordRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  return FirestoreSyncService(
    db: db,
    firestore: firestore,
    syncQueue: syncQueue,
    ledger: ledger,
    conflictRecords: conflictRecords,
    numbering: numbering,
  );
});

final fiscalPeriodRepositoryProvider = FutureProvider<FiscalPeriodRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return FiscalPeriodRepository(db, syncQueue);
});

final fixedAssetRepositoryProvider = FutureProvider<FixedAssetRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return FixedAssetRepository(db, syncQueue);
});

final approvalThresholdRepositoryProvider = FutureProvider<ApprovalThresholdRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return ApprovalThresholdRepository(db, syncQueue);
});

final depreciationServiceProvider = FutureProvider<DepreciationService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final assets = await ref.watch(fixedAssetRepositoryProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return DepreciationService(db, assets, ledger, syncQueue);
});

final salaryRepositoryProvider = FutureProvider<SalaryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return SalaryRepository(db, ledger, syncQueue);
});

final auditLogRepositoryProvider = FutureProvider<AuditLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return AuditLogRepository(db, syncQueue);
});

final expenseRepositoryProvider = FutureProvider<ExpenseRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  return ExpenseRepository(db, ledger);
});

final syncQueueRepositoryProvider = FutureProvider<SyncQueueRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SyncQueueRepository(db);
});

final conflictRecordRepositoryProvider = FutureProvider<ConflictRecordRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ConflictRecordRepository(db);
});

final balanceRollupRepositoryProvider = FutureProvider<BalanceRollupRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return BalanceRollupRepository(db);
});

final ledgerRepositoryProvider = FutureProvider<LedgerRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final fiscalPeriods = await ref.watch(fiscalPeriodRepositoryProvider.future);
  final auditLog = await ref.watch(auditLogRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final rollups = await ref.watch(balanceRollupRepositoryProvider.future);
  return LedgerRepository(db, fiscalPeriods, auditLog, syncQueue, rollups);
});

final taxRateRepositoryProvider = FutureProvider<TaxRateRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return TaxRateRepository(db, syncQueue);
});

final bankAccountRepositoryProvider = FutureProvider<BankAccountRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return BankAccountRepository(db, syncQueue);
});

final productRepositoryProvider = FutureProvider<ProductRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final auditLog = await ref.watch(auditLogRepositoryProvider.future);
  return ProductRepository(db, syncQueue, auditLog);
});

final categoryRepositoryProvider = FutureProvider<CategoryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return CategoryRepository(db, syncQueue);
});

final brandRepositoryProvider = FutureProvider<BrandRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return BrandRepository(db, syncQueue);
});

final partyRepositoryProvider = FutureProvider<PartyRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final rollups = await ref.watch(balanceRollupRepositoryProvider.future);
  return PartyRepository(db, syncQueue, rollups);
});

final numberSequenceServiceProvider = FutureProvider<NumberSequenceService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return NumberSequenceService(db);
});

final purchaseRepositoryProvider = FutureProvider<PurchaseRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final products = await ref.watch(productRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  final auditLog = await ref.watch(auditLogRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return PurchaseRepository(db, ledger, products, numbering, auditLog, syncQueue);
});

final saleRepositoryProvider = FutureProvider<SaleRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final products = await ref.watch(productRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  final approvalThresholds = await ref.watch(approvalThresholdRepositoryProvider.future);
  final auditLog = await ref.watch(auditLogRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return SaleRepository(db, ledger, products, numbering, approvalThresholds, auditLog, syncQueue);
});

final refundRepositoryProvider = FutureProvider<RefundRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final products = await ref.watch(productRepositoryProvider.future);
  final sales = await ref.watch(saleRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  final auditLog = await ref.watch(auditLogRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return RefundRepository(db, ledger, products, sales, numbering, auditLog, syncQueue);
});

final paymentRepositoryProvider = FutureProvider<PaymentRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return PaymentRepository(db, ledger, numbering, syncQueue);
});

// --- Shared across Fishery/Transport (OperatingAsset, Trip, TripExpense) ---

final operatingAssetRepositoryProvider = FutureProvider<OperatingAssetRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return OperatingAssetRepository(db, syncQueue);
});

final tripRepositoryProvider = FutureProvider<TripRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return TripRepository(db, syncQueue);
});

final tripExpenseRepositoryProvider = FutureProvider<TripExpenseRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final trips = await ref.watch(tripRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return TripExpenseRepository(db, ledger, trips, syncQueue);
});

// --- Fishery vertical ---

final fishCategoryRepositoryProvider = FutureProvider<FishCategoryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return FishCategoryRepository(db, syncQueue);
});

final catchRepositoryProvider = FutureProvider<CatchRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return CatchRepository(db, syncQueue);
});

final fishSaleRepositoryProvider = FutureProvider<FishSaleRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final trips = await ref.watch(tripRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return FishSaleRepository(db, ledger, trips, syncQueue);
});

final tripProfitServiceProvider = FutureProvider<TripProfitService>((ref) async {
  final fishSales = await ref.watch(fishSaleRepositoryProvider.future);
  final tripExpenses = await ref.watch(tripExpenseRepositoryProvider.future);
  return TripProfitService(fishSales, tripExpenses);
});

// --- Transport vertical ---

final contractRepositoryProvider = FutureProvider<ContractRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return ContractRepository(db, syncQueue);
});

final tripIncomeRepositoryProvider = FutureProvider<TripIncomeRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final trips = await ref.watch(tripRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return TripIncomeRepository(db, ledger, trips, syncQueue);
});

final weightEntryRepositoryProvider = FutureProvider<WeightEntryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return WeightEntryRepository(db, syncQueue);
});

final vehicleKhataRepositoryProvider = FutureProvider<VehicleKhataRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return VehicleKhataRepository(db, ledger, syncQueue);
});

final monthlySettlementRepositoryProvider = FutureProvider<MonthlySettlementRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final weightEntries = await ref.watch(weightEntryRepositoryProvider.future);
  final vehicleKhata = await ref.watch(vehicleKhataRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return MonthlySettlementRepository(db, ledger, weightEntries, vehicleKhata, syncQueue);
});

final vehicleProfitabilityServiceProvider = FutureProvider<VehicleProfitabilityService>((ref) async {
  final tripIncome = await ref.watch(tripIncomeRepositoryProvider.future);
  final khata = await ref.watch(vehicleKhataRepositoryProvider.future);
  return VehicleProfitabilityService(tripIncome, khata);
});

final driverPerformanceServiceProvider = FutureProvider<DriverPerformanceService>((ref) async {
  final tripIncome = await ref.watch(tripIncomeRepositoryProvider.future);
  final tripExpenses = await ref.watch(tripExpenseRepositoryProvider.future);
  return DriverPerformanceService(tripIncome, tripExpenses);
});

// --- In-app notifications (see lib/core/notifications/notification_item.dart) ---

final notificationCenterProvider = FutureProvider<List<NotificationItem>>((ref) async {
  final businessId = await ref.watch(currentBusinessIdProvider.future);
  final business = await ref.watch(currentBusinessProvider.future);
  final isReadOnly = await ref.watch(isReadOnlyProvider.future);
  final items = <NotificationItem>[];

  if (business.type == BusinessType.sparePartsShop) {
    final products = await ref.watch(productRepositoryProvider.future);
    final lowStock = (await products.list(businessId: businessId)).where((p) => p.stockQuantity <= p.reorderLevel).toList();
    if (lowStock.isNotEmpty) {
      items.add(NotificationItem(
        icon: Icons.inventory_2_outlined,
        color: AppColors.destructive,
        title: '${lowStock.length} product(s) low on stock',
        subtitle: lowStock.take(3).map((p) => p.name).join(', ') + (lowStock.length > 3 ? '…' : ''),
        navIndexHint: 'Products',
      ));
    }
  }

  if (!isReadOnly) {
    final sales = await ref.watch(saleRepositoryProvider.future);
    final pending = await sales.pendingApproval(businessId: businessId);
    if (pending.isNotEmpty) {
      items.add(NotificationItem(
        icon: Icons.hourglass_top,
        color: AppColors.warning,
        title: '${pending.length} sale(s) waiting on approval',
        subtitle: pending.take(3).map((s) => s.documentNumber).join(', ') + (pending.length > 3 ? '…' : ''),
        navIndexHint: 'Approvals',
      ));
    }
  }

  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final queueItems = await syncQueue.all(businessId: businessId);
  final failed = queueItems.where((i) => i.status == SyncQueueStatus.failed).length;
  if (failed > 0) {
    items.add(NotificationItem(
      icon: Icons.error_outline,
      color: AppColors.destructive,
      title: '$failed item(s) failed to sync',
      subtitle: 'Check Sync Status for details',
      navIndexHint: 'Sync Status',
    ));
  }

  final conflictRecords = await ref.watch(conflictRecordRepositoryProvider.future);
  final conflicts = await conflictRecords.unresolved(businessId: businessId);
  if (conflicts.isNotEmpty) {
    items.add(NotificationItem(
      icon: Icons.warning_amber,
      color: AppColors.accent,
      title: '${conflicts.length} sync conflict(s) need a decision',
      subtitle: 'Check Sync Status for details',
      navIndexHint: 'Sync Status',
    ));
  }

  return items;
});
