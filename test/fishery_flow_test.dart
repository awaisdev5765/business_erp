import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/activity/trip.dart';
import 'package:business_erp/core/activity/trip_repository.dart';
import 'package:business_erp/core/asset/operating_asset.dart';
import 'package:business_erp/core/asset/operating_asset_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/features/fishery/catch_repository.dart';
import 'package:business_erp/features/fishery/fish_sale.dart';
import 'package:business_erp/features/fishery/fish_sale_repository.dart';
import 'package:business_erp/features/fishery/trip_expense.dart';
import 'package:business_erp/features/fishery/trip_expense_repository.dart';
import 'package:business_erp/features/fishery/trip_profit_service.dart';

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
  late FishCategoryRepository fishCategories;
  late CatchRepository catches;
  late FishSaleRepository fishSales;
  late TripProfitService tripProfit;

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
    fishCategories = FishCategoryRepository(db);
    catches = CatchRepository(db);
    fishSales = FishSaleRepository(db, ledger, trips);
    tripProfit = TripProfitService(fishSales, tripExpenses);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('full fishery trip: boat + captain registered, trip planned/started/completed, '
      'expenses and catch sale post to the right accounts, Boat Ledger shows both, '
      'and Trip Profit nets revenue minus expenses', () async {
    final boat = await assets.create(businessId: businessId, type: OperatingAssetType.boat, name: 'Sea Hawk');
    final captain = await parties.create(businessId: businessId, type: PartyType.captain, name: 'Captain Silva');

    final trip = await trips.create(
      businessId: businessId,
      tripType: TripType.fishery,
      assetUuid: boat.uuid,
      captainUuid: captain.uuid,
    );
    expect(trip.status, TripStatus.planned);

    await trips.start(trip.uuid);
    var reloaded = await trips.findByUuid(trip.uuid);
    expect(reloaded!.status, TripStatus.inProgress);

    // Fuel expense: 3000, Ice expense: 500.
    await tripExpenses.record(
      businessId: businessId,
      tripUuid: trip.uuid,
      category: TripExpenseCategory.fuel,
      amountMinorUnits: 3000,
      createdBy: user,
      deviceId: deviceId,
    );
    await tripExpenses.record(
      businessId: businessId,
      tripUuid: trip.uuid,
      category: TripExpenseCategory.ice,
      amountMinorUnits: 500,
      createdBy: user,
      deviceId: deviceId,
    );

    final fuelBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5020');
    expect(fuelBalance, 3000);
    final iceBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5040');
    expect(iceBalance, 500);
    final cashAfterExpenses = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashAfterExpenses, -3500);

    final tuna = await fishCategories.create(businessId: businessId, name: 'Tuna');
    await catches.record(
      tripUuid: trip.uuid,
      businessId: businessId,
      fishCategoryUuid: tuna.uuid,
      weightKg: 100,
      estimatedValueMinorUnits: 10000,
    );

    // Sell 100kg at 150/kg (minor units) = 15000 cash sale.
    await fishSales.create(
      businessId: businessId,
      tripUuid: trip.uuid,
      fishCategoryUuid: tuna.uuid,
      weightKg: 100,
      unitPriceMinorUnitsPerKg: 150,
      paymentMethod: FishSalePaymentMethod.cash,
      createdBy: user,
      deviceId: deviceId,
    );

    final tripIncome = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '4020');
    expect(tripIncome, -15000);
    final cashAfterSale = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashAfterSale, 11500); // -3500 + 15000

    await trips.complete(trip.uuid);
    reloaded = await trips.findByUuid(trip.uuid);
    expect(reloaded!.status, TripStatus.completed);
    expect(reloaded.endDate, isNotNull);

    // Boat Ledger: every journal line tagged with this boat, across all accounts.
    final boatLedger = await ledger.dimensionStatement(businessId: businessId, dimensionUuid: boat.uuid);
    final accountCodes = boatLedger.map((row) => row['account_code']).toSet();
    expect(accountCodes, {'5020', '1010', '5040', '4020'});

    // Trip Profit = 15000 revenue - 3500 expenses = 11500.
    final profit = await tripProfit.forTrip(trip.uuid);
    expect(profit.revenueMinorUnits, 15000);
    expect(profit.expenseMinorUnits, 3500);
    expect(profit.profitMinorUnits, 11500);
  });

  test('credit fish sale requires a customer', () async {
    final boat = await assets.create(businessId: businessId, type: OperatingAssetType.boat, name: 'Sea Hawk');
    final trip = await trips.create(businessId: businessId, tripType: TripType.fishery, assetUuid: boat.uuid);
    final tuna = await fishCategories.create(businessId: businessId, name: 'Tuna');

    expect(
      () => fishSales.create(
        businessId: businessId,
        tripUuid: trip.uuid,
        fishCategoryUuid: tuna.uuid,
        weightKg: 10,
        unitPriceMinorUnitsPerKg: 100,
        paymentMethod: FishSalePaymentMethod.credit,
        createdBy: user,
        deviceId: deviceId,
      ),
      throwsArgumentError,
    );
  });
}
