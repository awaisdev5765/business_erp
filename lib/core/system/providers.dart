import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/approval_threshold_repository.dart';
import '../accounting/balance_rollup_repository.dart';
import '../accounting/bank_account_repository.dart';
import '../accounting/chart_of_accounts_seed.dart';
import '../accounting/depreciation_service.dart';
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
import '../party/party_repository.dart';
import '../sync/conflict_record_repository.dart';
import '../sync/firestore_sync_service.dart';
import '../sync/sync_queue_repository.dart';
import '../tenant/business.dart';
import '../tenant/business_repository.dart';
import '../transaction/payment_repository.dart';
import '../transaction/salary_repository.dart';
import '../../features/fishery/catch_repository.dart';
import '../../features/fishery/fish_sale_repository.dart';
import '../../features/fishery/trip_profit_service.dart';
import '../../features/spare_parts/inventory/category_repository.dart';
import '../../features/spare_parts/inventory/product_repository.dart';
import '../../features/spare_parts/purchases/purchase_repository.dart';
import '../../features/spare_parts/sales/sale_repository.dart';
import '../../features/transport/contract_repository.dart';
import '../../features/transport/driver_performance_service.dart';
import '../../features/transport/trip_income_repository.dart';
import '../../features/transport/vehicle_profitability_service.dart';
import 'audit_log_repository.dart';
import 'database.dart';
import 'number_sequence_service.dart';

const _uuid = Uuid();

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

final currentBusinessIdProvider = FutureProvider<String>((ref) async {
  final db = await ref.watch(databaseProvider.future);

  final selected = ref.watch(selectedBusinessIdProvider);
  if (selected != null) {
    await seedChartOfAccounts(db, selected); // idempotent top-up, see seedChartOfAccounts
    return selected;
  }

  final rows = await db.query(Business.tableName, limit: 1);
  if (rows.isNotEmpty) {
    final businessId = rows.first['uuid'] as String;
    await seedChartOfAccounts(db, businessId);
    return businessId;
  }

  final now = DateTime.now();
  final business = Business(
    uuid: _uuid.v4(),
    name: 'My Spare Parts Shop',
    type: BusinessType.sparePartsShop,
    createdAt: now,
    updatedAt: now,
  );
  await db.insert(Business.tableName, business.toMap());
  await seedChartOfAccounts(db, business.uuid);
  return business.uuid;
});

final businessRepositoryProvider = FutureProvider<BusinessRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return BusinessRepository(db);
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

final firestoreSyncServiceProvider = FutureProvider<FirestoreSyncService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final firestore = ref.watch(firestoreProvider);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final conflictRecords = await ref.watch(conflictRecordRepositoryProvider.future);
  return FirestoreSyncService(
    db: db,
    firestore: firestore,
    syncQueue: syncQueue,
    ledger: ledger,
    conflictRecords: conflictRecords,
  );
});

final fiscalPeriodRepositoryProvider = FutureProvider<FiscalPeriodRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FiscalPeriodRepository(db);
});

final fixedAssetRepositoryProvider = FutureProvider<FixedAssetRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FixedAssetRepository(db);
});

final approvalThresholdRepositoryProvider = FutureProvider<ApprovalThresholdRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ApprovalThresholdRepository(db);
});

final depreciationServiceProvider = FutureProvider<DepreciationService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final assets = await ref.watch(fixedAssetRepositoryProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  return DepreciationService(db, assets, ledger);
});

final salaryRepositoryProvider = FutureProvider<SalaryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  return SalaryRepository(db, ledger);
});

final auditLogRepositoryProvider = FutureProvider<AuditLogRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return AuditLogRepository(db);
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
  return TaxRateRepository(db);
});

final bankAccountRepositoryProvider = FutureProvider<BankAccountRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return BankAccountRepository(db);
});

final productRepositoryProvider = FutureProvider<ProductRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return ProductRepository(db, syncQueue);
});

final categoryRepositoryProvider = FutureProvider<CategoryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return CategoryRepository(db);
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
  return PurchaseRepository(db, ledger, products, numbering);
});

final saleRepositoryProvider = FutureProvider<SaleRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final products = await ref.watch(productRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  final approvalThresholds = await ref.watch(approvalThresholdRepositoryProvider.future);
  return SaleRepository(db, ledger, products, numbering, approvalThresholds);
});

final paymentRepositoryProvider = FutureProvider<PaymentRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final numbering = await ref.watch(numberSequenceServiceProvider.future);
  return PaymentRepository(db, ledger, numbering);
});

// --- Shared across Fishery/Transport (OperatingAsset, Trip, TripExpense) ---

final operatingAssetRepositoryProvider = FutureProvider<OperatingAssetRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return OperatingAssetRepository(db);
});

final tripRepositoryProvider = FutureProvider<TripRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TripRepository(db);
});

final tripExpenseRepositoryProvider = FutureProvider<TripExpenseRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final trips = await ref.watch(tripRepositoryProvider.future);
  return TripExpenseRepository(db, ledger, trips);
});

// --- Fishery vertical ---

final fishCategoryRepositoryProvider = FutureProvider<FishCategoryRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FishCategoryRepository(db);
});

final catchRepositoryProvider = FutureProvider<CatchRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return CatchRepository(db);
});

final fishSaleRepositoryProvider = FutureProvider<FishSaleRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final trips = await ref.watch(tripRepositoryProvider.future);
  return FishSaleRepository(db, ledger, trips);
});

final tripProfitServiceProvider = FutureProvider<TripProfitService>((ref) async {
  final fishSales = await ref.watch(fishSaleRepositoryProvider.future);
  final tripExpenses = await ref.watch(tripExpenseRepositoryProvider.future);
  return TripProfitService(fishSales, tripExpenses);
});

// --- Transport vertical ---

final contractRepositoryProvider = FutureProvider<ContractRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ContractRepository(db);
});

final tripIncomeRepositoryProvider = FutureProvider<TripIncomeRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  final trips = await ref.watch(tripRepositoryProvider.future);
  return TripIncomeRepository(db, ledger, trips);
});

final vehicleProfitabilityServiceProvider = FutureProvider<VehicleProfitabilityService>((ref) async {
  final tripIncome = await ref.watch(tripIncomeRepositoryProvider.future);
  final tripExpenses = await ref.watch(tripExpenseRepositoryProvider.future);
  return VehicleProfitabilityService(tripIncome, tripExpenses);
});

final driverPerformanceServiceProvider = FutureProvider<DriverPerformanceService>((ref) async {
  final tripIncome = await ref.watch(tripIncomeRepositoryProvider.future);
  final tripExpenses = await ref.watch(tripExpenseRepositoryProvider.future);
  return DriverPerformanceService(tripIncome, tripExpenses);
});
