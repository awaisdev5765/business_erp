import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/approval_threshold_repository.dart';
import 'package:business_erp/core/accounting/bank_account_repository.dart';
import 'package:business_erp/core/accounting/depreciation_service.dart';
import 'package:business_erp/core/accounting/fixed_asset_repository.dart';
import 'package:business_erp/core/accounting/fiscal_period_repository.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/accounting/tax_rate_repository.dart';
import 'package:business_erp/core/activity/trip.dart';
import 'package:business_erp/core/activity/trip_expense.dart';
import 'package:business_erp/core/activity/trip_expense_repository.dart';
import 'package:business_erp/core/activity/trip_repository.dart';
import 'package:business_erp/core/asset/operating_asset.dart';
import 'package:business_erp/core/asset/operating_asset_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/sync/conflict_record_repository.dart';
import 'package:business_erp/core/sync/firestore_sync_service.dart';
import 'package:business_erp/core/sync/sync_queue_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/system/number_sequence_service.dart';
import 'package:business_erp/core/tenant/business.dart';
import 'package:business_erp/core/tenant/business_repository.dart';
import 'package:business_erp/core/transaction/payment.dart';
import 'package:business_erp/core/transaction/payment_repository.dart';
import 'package:business_erp/core/transaction/salary_repository.dart';
import 'package:business_erp/features/fishery/catch_repository.dart';
import 'package:business_erp/features/fishery/fish_sale.dart';
import 'package:business_erp/features/fishery/fish_sale_repository.dart';
import 'package:business_erp/features/spare_parts/inventory/brand_repository.dart';
import 'package:business_erp/features/spare_parts/inventory/category_repository.dart';
import 'package:business_erp/features/spare_parts/inventory/product_repository.dart';
import 'package:business_erp/features/spare_parts/sales/sale.dart';
import 'package:business_erp/features/spare_parts/sales/sale_repository.dart';
import 'package:business_erp/features/transport/contract_repository.dart';
import 'package:business_erp/features/transport/trip_income.dart';
import 'package:business_erp/features/transport/trip_income_repository.dart';

/// The "fix all gaps" follow-up to business_restore_test.dart: proves the
/// restore path also covers Fishery, Transport, Payroll, Fixed Assets,
/// Bank Reconciliation, and the Category/Brand/TaxRate/FiscalPeriod/
/// ApprovalThreshold registries — not just Spare Parts' Sale/Purchase/
/// Refund — plus that document numbering survives a restore without
/// reissuing an already-used number.
void main() {
  late Directory tempDirA;
  late Directory tempDirB;
  late Database dbA;
  late Database dbB;
  late FakeFirebaseFirestore firestore;
  const user = 'tester';
  const deviceId = 'device-1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirA = await Directory.systemTemp.createTemp('device_a_');
    tempDirB = await Directory.systemTemp.createTemp('device_b_');
    dbA = await databaseFactory.openDatabase(
      '${tempDirA.path}/test.db',
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
    );
    dbB = await databaseFactory.openDatabase(
      '${tempDirB.path}/test.db',
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
    );
    firestore = FakeFirebaseFirestore();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
    await tempDirA.delete(recursive: true);
    await tempDirB.delete(recursive: true);
  });

  test('restoreFromCloud covers Fishery, Transport, Payroll, Fixed Assets, Bank Reconciliation, and the shared registries', () async {
    final syncQueueA = SyncQueueRepository(dbA);
    final ledgerA = LedgerRepository(dbA, null, null, syncQueueA);
    final numberingA = NumberSequenceService(dbA);
    final businessesA = BusinessRepository(dbA, syncQueueA);
    final partiesA = PartyRepository(dbA, syncQueueA);
    final categoriesA = CategoryRepository(dbA, syncQueueA);
    final brandsA = BrandRepository(dbA, syncQueueA);
    final assetsA = OperatingAssetRepository(dbA, syncQueueA);
    final tripsA = TripRepository(dbA, syncQueueA);
    final tripExpensesA = TripExpenseRepository(dbA, ledgerA, tripsA, syncQueueA);
    final fishCategoriesA = FishCategoryRepository(dbA, syncQueueA);
    final catchesA = CatchRepository(dbA, syncQueueA);
    final fishSalesA = FishSaleRepository(dbA, ledgerA, tripsA, syncQueueA);
    final contractsA = ContractRepository(dbA, syncQueueA);
    final tripIncomeA = TripIncomeRepository(dbA, ledgerA, tripsA, syncQueueA);
    final paymentsA = PaymentRepository(dbA, ledgerA, numberingA, syncQueueA);
    final salaryA = SalaryRepository(dbA, ledgerA, syncQueueA);
    final fixedAssetsA = FixedAssetRepository(dbA, syncQueueA);
    final depreciationA = DepreciationService(dbA, fixedAssetsA, ledgerA, syncQueueA);
    final bankAccountsA = BankAccountRepository(dbA, syncQueueA);
    final fiscalPeriodsA = FiscalPeriodRepository(dbA, syncQueueA);
    final taxRatesA = TaxRateRepository(dbA, syncQueueA);
    final approvalThresholdsA = ApprovalThresholdRepository(dbA, syncQueueA);
    final syncA = FirestoreSyncService(
      db: dbA, firestore: firestore, syncQueue: syncQueueA, ledger: ledgerA,
      conflictRecords: ConflictRecordRepository(dbA), numbering: numberingA,
    );

    final business = await businessesA.create(name: 'Multi-Vertical Co', type: BusinessType.fishery, baseCurrency: 'USD');
    final captain = await partiesA.create(businessId: business.uuid, type: PartyType.captain, name: 'Captain Ahab');
    final customer = await partiesA.create(businessId: business.uuid, type: PartyType.customer, name: 'Fish Buyer');
    final employee = await partiesA.create(businessId: business.uuid, type: PartyType.employee, name: 'Office Staff');

    await categoriesA.create(businessId: business.uuid, name: 'Engine Parts');
    await brandsA.create(businessId: business.uuid, name: 'Yamaha');

    final boat = await assetsA.create(businessId: business.uuid, type: OperatingAssetType.boat, name: 'The Pequod');
    final trip = await tripsA.create(businessId: business.uuid, tripType: TripType.fishery, assetUuid: boat.uuid, captainUuid: captain.uuid);
    await tripExpensesA.record(
      businessId: business.uuid, tripUuid: trip.uuid, category: TripExpenseCategory.fuel,
      amountMinorUnits: 5000, createdBy: user, deviceId: deviceId,
    );
    final fishCategory = await fishCategoriesA.create(businessId: business.uuid, name: 'Tuna');
    await catchesA.record(tripUuid: trip.uuid, businessId: business.uuid, fishCategoryUuid: fishCategory.uuid, weightKg: 50);
    await fishSalesA.create(
      businessId: business.uuid, tripUuid: trip.uuid, customerUuid: customer.uuid, fishCategoryUuid: fishCategory.uuid,
      weightKg: 50, unitPriceMinorUnitsPerKg: 200, paymentMethod: FishSalePaymentMethod.credit,
      createdBy: user, deviceId: deviceId,
    );

    final contract = await contractsA.create(businessId: business.uuid, customerUuid: customer.uuid, description: 'Monthly haul contract');
    await tripIncomeA.create(
      businessId: business.uuid, tripUuid: trip.uuid, customerUuid: customer.uuid, contractUuid: contract.uuid,
      amountMinorUnits: 30000, paymentMethod: TripIncomePaymentMethod.credit, createdBy: user, deviceId: deviceId,
    );

    await paymentsA.record(
      businessId: business.uuid, partyUuid: customer.uuid, direction: PaymentDirection.receiveFromCustomer,
      amountMinorUnits: 10000, createdBy: user, deviceId: deviceId,
    );

    final salaryRecord = await salaryA.createRecord(businessId: business.uuid, partyUuid: employee.uuid, amountMinorUnits: 50000);
    await salaryA.paySalary(record: salaryRecord, period: '2026-01', createdBy: user, deviceId: deviceId);

    final fixedAsset = await fixedAssetsA.create(
      businessId: business.uuid, name: 'Office Generator', acquisitionDate: DateTime(2026, 1, 1),
      acquisitionCostMinorUnits: 120000, usefulLifeMonths: 12,
    );
    await depreciationA.postMonthlyDepreciation(fixedAssetUuid: fixedAsset.uuid, period: '2026-01', createdBy: user, deviceId: deviceId);

    final bankAccount = await bankAccountsA.create(businessId: business.uuid, name: 'Main Checking', openingBalanceMinorUnits: 100000);
    await bankAccountsA.addStatementLine(
      bankAccountUuid: bankAccount.uuid, date: DateTime(2026, 1, 5), description: 'Deposit', amountMinorUnits: 5000,
    );

    await fiscalPeriodsA.create(businessId: business.uuid, startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 31));
    await taxRatesA.create(businessId: business.uuid, name: 'Standard VAT', ratePercent: 15);
    await approvalThresholdsA.setThreshold(businessId: business.uuid, transactionType: 'sale', thresholdMinorUnits: 1000000);

    await syncA.uploadPending(business.uuid);

    // --- Device B: wiped local storage.
    final syncQueueB = SyncQueueRepository(dbB);
    final ledgerB = LedgerRepository(dbB, null, null, syncQueueB);
    final numberingB = NumberSequenceService(dbB);
    final syncB = FirestoreSyncService(
      db: dbB, firestore: firestore, syncQueue: syncQueueB, ledger: ledgerB,
      conflictRecords: ConflictRecordRepository(dbB), numbering: numberingB,
    );

    final restored = await syncB.restoreFromCloud(isSuperAdmin: true, businessAccess: const {});
    expect(restored, true);

    Future<List<Map<String, Object?>>> rows(String table) => dbB.query(table, where: 'business_id = ?', whereArgs: [business.uuid]);

    expect((await dbB.query(Business.tableName)).single['name'], 'Multi-Vertical Co');
    expect((await rows('categories')).single['name'], 'Engine Parts');
    expect((await rows('brands')).single['name'], 'Yamaha');
    expect((await rows('operating_assets')).single['name'], 'The Pequod');
    expect((await rows('trips')).single['asset_uuid'], boat.uuid);
    expect((await rows('trip_expenses')).single['amount_minor_units'], 5000);
    expect((await rows('fish_categories')).single['name'], 'Tuna');
    expect((await rows('catch_entries')).single['weight_kg'], 50.0);
    expect((await rows('fish_sales')).single['trip_uuid'], trip.uuid);
    expect((await rows('contracts')).single['description'], 'Monthly haul contract');
    expect((await rows('trip_incomes')).single['amount_minor_units'], 30000);
    expect((await rows('payments')).single['amount_minor_units'], 10000);
    expect((await rows('salary_records')).single['amount_minor_units'], 50000);
    expect((await rows('salary_payments')).single['period'], '2026-01');
    expect((await rows('fixed_assets')).single['name'], 'Office Generator');
    expect((await rows('depreciation_entries')).single['period'], '2026-01');
    expect((await rows('bank_accounts')).single['name'], 'Main Checking');
    final restoredBankAccount = (await rows('bank_accounts')).single;
    final statementLines = await dbB.query('bank_statement_lines', where: 'bank_account_uuid = ?', whereArgs: [restoredBankAccount['uuid']]);
    expect(statementLines.single['description'], 'Deposit');
    expect((await rows('fiscal_periods')).single['status'], 'open');
    expect((await rows('tax_rates')).single['name'], 'Standard VAT');
    final approvalThresholds = await dbB.query('approval_thresholds', where: 'business_id = ? AND transaction_type = ?', whereArgs: [business.uuid, 'sale']);
    expect(approvalThresholds.single['threshold_minor_units'], 1000000);

    // The ledger itself restored too, so the boat's trip expense, fish
    // sale, and trip income all show up in the dimension-scoped Boat
    // Ledger (each posts 2 dimension-tagged lines).
    final boatLines = await ledgerB.dimensionStatement(businessId: business.uuid, dimensionUuid: boat.uuid);
    expect(boatLines.length, 6);
  });

  test('document numbering resyncs from issued numbers, so a restored device never reissues an already-used number', () async {
    final syncQueueA = SyncQueueRepository(dbA);
    final ledgerA = LedgerRepository(dbA, null, null, syncQueueA);
    final productsA = ProductRepository(dbA, syncQueueA);
    final numberingA = NumberSequenceService(dbA);
    final businessesA = BusinessRepository(dbA, syncQueueA);
    final salesA = SaleRepository(dbA, ledgerA, productsA, numberingA, null, null, syncQueueA);
    final syncA = FirestoreSyncService(
      db: dbA, firestore: firestore, syncQueue: syncQueueA, ledger: ledgerA,
      conflictRecords: ConflictRecordRepository(dbA), numbering: numberingA,
    );

    final business = await businessesA.create(name: 'Numbering Co', type: BusinessType.sparePartsShop);
    final product = await productsA.create(
      businessId: business.uuid, sku: 'X-1', name: 'Widget', costPriceMinorUnits: 100, salePriceMinorUnits: 200, openingStock: 100,
    );

    final firstSale = await salesA.create(
      businessId: business.uuid, paymentMethod: PaymentMethod.cash, createdBy: user, deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 200)],
    );
    final secondSale = await salesA.create(
      businessId: business.uuid, paymentMethod: PaymentMethod.cash, createdBy: user, deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 200)],
    );
    expect(firstSale.documentNumber, endsWith('000001'));
    expect(secondSale.documentNumber, endsWith('000002'));

    await syncA.uploadPending(business.uuid);

    final syncQueueB = SyncQueueRepository(dbB);
    final ledgerB = LedgerRepository(dbB, null, null, syncQueueB);
    final productsB = ProductRepository(dbB);
    final numberingB = NumberSequenceService(dbB);
    final syncB = FirestoreSyncService(
      db: dbB, firestore: firestore, syncQueue: syncQueueB, ledger: ledgerB,
      conflictRecords: ConflictRecordRepository(dbB), numbering: numberingB,
    );

    await syncB.restoreFromCloud(isSuperAdmin: true, businessAccess: const {});

    final salesB = SaleRepository(dbB, ledgerB, productsB, numberingB);
    final thirdSale = await salesB.create(
      businessId: business.uuid, paymentMethod: PaymentMethod.cash, createdBy: user, deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 1, unitPriceMinorUnits: 200)],
    );

    // Without the resync fix-up, this would come back as 000001 again —
    // a duplicate of firstSale's already-issued number.
    expect(thirdSale.documentNumber, endsWith('000003'));
  });
}
