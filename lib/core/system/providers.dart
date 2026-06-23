import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/bank_account_repository.dart';
import '../accounting/chart_of_accounts_seed.dart';
import '../accounting/fiscal_period_repository.dart';
import '../accounting/ledger_repository.dart';
import '../accounting/tax_rate_repository.dart';
import '../activity/trip_expense_repository.dart';
import '../activity/trip_repository.dart';
import '../asset/operating_asset_repository.dart';
import '../identity/user_profile_repository.dart';
import '../party/party_repository.dart';
import '../sync/conflict_record_repository.dart';
import '../sync/firestore_sync_service.dart';
import '../sync/sync_queue_repository.dart';
import '../tenant/business.dart';
import '../transaction/payment_repository.dart';
import '../../features/fishery/catch_repository.dart';
import '../../features/fishery/fish_sale_repository.dart';
import '../../features/fishery/trip_profit_service.dart';
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

/// Single demo business + single device/user identity for Phase 1. Real
/// multi-business switching and auth land in Phase 5 (see PHASES.md) —
/// until then, the app boots straight into one seeded business so the
/// transactional screens are usable end-to-end.
final databaseProvider = FutureProvider<Database>((ref) async {
  final db = await AppDatabase.open();
  return db;
});

final currentBusinessIdProvider = FutureProvider<String>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final rows = await db.query(Business.tableName, limit: 1);
  if (rows.isNotEmpty) {
    return rows.first['uuid'] as String;
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

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository(ref.watch(firestoreProvider));
});

final firestoreSyncServiceProvider = FutureProvider<FirestoreSyncService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final firestore = ref.watch(firestoreProvider);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  return FirestoreSyncService(db: db, firestore: firestore, syncQueue: syncQueue, ledger: ledger);
});

final fiscalPeriodRepositoryProvider = FutureProvider<FiscalPeriodRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return FiscalPeriodRepository(db);
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

final ledgerRepositoryProvider = FutureProvider<LedgerRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final fiscalPeriods = await ref.watch(fiscalPeriodRepositoryProvider.future);
  final auditLog = await ref.watch(auditLogRepositoryProvider.future);
  final syncQueue = await ref.watch(syncQueueRepositoryProvider.future);
  return LedgerRepository(db, fiscalPeriods, auditLog, syncQueue);
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
  return ProductRepository(db);
});

final partyRepositoryProvider = FutureProvider<PartyRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PartyRepository(db);
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
  return SaleRepository(db, ledger, products, numbering);
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
