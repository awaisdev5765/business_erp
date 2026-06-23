import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/activity/trip.dart';
import 'package:business_erp/core/activity/trip_expense.dart';
import 'package:business_erp/core/activity/trip_expense_repository.dart';
import 'package:business_erp/core/activity/trip_repository.dart';
import 'package:business_erp/core/asset/operating_asset.dart';
import 'package:business_erp/core/asset/operating_asset_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/features/transport/contract_repository.dart';
import 'package:business_erp/features/transport/driver_performance_service.dart';
import 'package:business_erp/features/transport/trip_income.dart';
import 'package:business_erp/features/transport/trip_income_repository.dart';
import 'package:business_erp/features/transport/vehicle_profitability_service.dart';

void main() {
  late Database db;
  late Directory tempDir;
  const businessId = 'business-1';
  const deviceId = 'device-1';
  const user = 'tester';

  late LedgerRepository ledger;
  late OperatingAssetRepository assets;
  late TripRepository trips;
  late PartyRepository parties;
  late TripExpenseRepository tripExpenses;
  late ContractRepository contracts;
  late TripIncomeRepository tripIncomes;
  late VehicleProfitabilityService vehicleProfitability;
  late DriverPerformanceService driverPerformance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlite_test_');
    db = await databaseFactory.openDatabase(
      '${tempDir.path}/test.db',
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
    );
    await seedChartOfAccounts(db, businessId);

    ledger = LedgerRepository(db);
    assets = OperatingAssetRepository(db);
    trips = TripRepository(db);
    parties = PartyRepository(db);
    tripExpenses = TripExpenseRepository(db, ledger, trips);
    contracts = ContractRepository(db);
    tripIncomes = TripIncomeRepository(db, ledger, trips);
    vehicleProfitability = VehicleProfitabilityService(tripIncomes, tripExpenses);
    driverPerformance = DriverPerformanceService(tripIncomes, tripExpenses);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('full transport trip: vehicle + driver + contract registered, expenses '
      '(fuel/repair/tyre/oil) and trip income post to the right accounts, Vehicle '
      'Ledger shows everything, and Vehicle Profitability / Driver Performance roll up '
      'correctly across two trips', () async {
    final vehicle = await assets.create(businessId: businessId, type: OperatingAssetType.vehicle, name: 'Truck 01');
    final driver = await parties.create(businessId: businessId, type: PartyType.driver, name: 'Driver Perera');
    final company = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Acme Logistics');
    final contract = await contracts.create(
      businessId: businessId,
      customerUuid: company.uuid,
      description: 'Weekly Colombo-Kandy haul',
      ratePerTripMinorUnits: 20000,
    );

    // Trip 1: fuel + repair expenses, cash trip income.
    final trip1 = await trips.create(
      businessId: businessId,
      tripType: TripType.transport,
      assetUuid: vehicle.uuid,
      captainUuid: driver.uuid,
    );
    await trips.start(trip1.uuid);

    await tripExpenses.record(
      businessId: businessId,
      tripUuid: trip1.uuid,
      category: TripExpenseCategory.fuel,
      amountMinorUnits: 4000,
      createdBy: user,
      deviceId: deviceId,
    );
    await tripExpenses.record(
      businessId: businessId,
      tripUuid: trip1.uuid,
      category: TripExpenseCategory.repair,
      amountMinorUnits: 1500,
      createdBy: user,
      deviceId: deviceId,
    );

    await tripIncomes.create(
      businessId: businessId,
      tripUuid: trip1.uuid,
      contractUuid: contract.uuid,
      amountMinorUnits: 20000,
      paymentMethod: TripIncomePaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
    );
    await trips.complete(trip1.uuid);

    final fuelBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5020');
    expect(fuelBalance, 4000);
    final repairBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5060');
    expect(repairBalance, 1500);
    final tripIncomeBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '4020');
    expect(tripIncomeBalance, -20000);

    // Trip 2: tyre + oil expenses, credit trip income to the same company.
    final trip2 = await trips.create(
      businessId: businessId,
      tripType: TripType.transport,
      assetUuid: vehicle.uuid,
      captainUuid: driver.uuid,
    );
    await trips.start(trip2.uuid);

    await tripExpenses.record(
      businessId: businessId,
      tripUuid: trip2.uuid,
      category: TripExpenseCategory.tyre,
      amountMinorUnits: 3000,
      createdBy: user,
      deviceId: deviceId,
    );
    await tripExpenses.record(
      businessId: businessId,
      tripUuid: trip2.uuid,
      category: TripExpenseCategory.oil,
      amountMinorUnits: 800,
      createdBy: user,
      deviceId: deviceId,
    );

    await tripIncomes.create(
      businessId: businessId,
      tripUuid: trip2.uuid,
      customerUuid: company.uuid,
      contractUuid: contract.uuid,
      amountMinorUnits: 20000,
      paymentMethod: TripIncomePaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
    );
    await trips.complete(trip2.uuid);

    final companyReceivable = await parties.outstandingBalanceMinorUnits(company.uuid);
    expect(companyReceivable, 20000); // only trip2 was credit

    // Vehicle Ledger: every account touched by this vehicle across both trips.
    final vehicleLedger = await ledger.dimensionStatement(businessId: businessId, dimensionUuid: vehicle.uuid);
    final accountCodes = vehicleLedger.map((row) => row['account_code']).toSet();
    expect(accountCodes, {'5020', '5060', '1010', '4020', '5070', '5080', '1030'});

    // Vehicle Profitability across both trips:
    // revenue = 20000 + 20000 = 40000; expenses = 4000+1500+3000+800 = 9300.
    final vehicleProfit = await vehicleProfitability.forAsset(vehicle.uuid);
    expect(vehicleProfit.revenueMinorUnits, 40000);
    expect(vehicleProfit.expenseMinorUnits, 9300);
    expect(vehicleProfit.profitMinorUnits, 30700);

    // Driver Performance should match exactly (same driver on both trips).
    final driverPerf = await driverPerformance.forDriver(driver.uuid);
    expect(driverPerf.revenueMinorUnits, 40000);
    expect(driverPerf.expenseMinorUnits, 9300);
    expect(driverPerf.profitMinorUnits, 30700);
  });

  test('credit trip income requires a customer', () async {
    final vehicle = await assets.create(businessId: businessId, type: OperatingAssetType.vehicle, name: 'Truck 01');
    final trip = await trips.create(businessId: businessId, tripType: TripType.transport, assetUuid: vehicle.uuid);

    expect(
      () => tripIncomes.create(
        businessId: businessId,
        tripUuid: trip.uuid,
        amountMinorUnits: 5000,
        paymentMethod: TripIncomePaymentMethod.credit,
        createdBy: user,
        deviceId: deviceId,
      ),
      throwsArgumentError,
    );
  });
}
