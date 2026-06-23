import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/depreciation_service.dart';
import 'package:business_erp/core/accounting/fixed_asset_repository.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late FixedAssetRepository assets;
  late DepreciationService depreciation;
  late LedgerRepository ledger;
  const businessId = 'business-1';
  const user = 'tester';
  const deviceId = 'device-1';

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
    assets = FixedAssetRepository(db);
    ledger = LedgerRepository(db);
    depreciation = DepreciationService(db, assets, ledger);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('straight-line monthly depreciation posts Dr Depreciation Expense / Cr Accumulated Depreciation', () async {
    final asset = await assets.create(
      businessId: businessId,
      name: 'Delivery Van',
      acquisitionDate: DateTime(2026, 1, 1),
      acquisitionCostMinorUnits: 1200000, // 12,000.00
      usefulLifeMonths: 12,
      salvageValueMinorUnits: 0,
    );
    expect(asset.monthlyDepreciationMinorUnits, 100000); // 1000.00/month

    await depreciation.postMonthlyDepreciation(
      fixedAssetUuid: asset.uuid,
      period: '2026-01',
      createdBy: user,
      deviceId: deviceId,
    );

    final expenseBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '5090');
    expect(expenseBalance, 100000);
    final accumulatedBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1060');
    expect(accumulatedBalance, -100000); // credit balance

    final bookValue = await assets.bookValue(asset);
    expect(bookValue, 1100000);
  });

  test('the same asset/period cannot be depreciated twice', () async {
    final asset = await assets.create(
      businessId: businessId,
      name: 'Delivery Van',
      acquisitionDate: DateTime(2026, 1, 1),
      acquisitionCostMinorUnits: 1200000,
      usefulLifeMonths: 12,
    );

    await depreciation.postMonthlyDepreciation(
      fixedAssetUuid: asset.uuid,
      period: '2026-01',
      createdBy: user,
      deviceId: deviceId,
    );

    expect(
      () => depreciation.postMonthlyDepreciation(
        fixedAssetUuid: asset.uuid,
        period: '2026-01',
        createdBy: user,
        deviceId: deviceId,
      ),
      throwsStateError,
    );
  });

  test('the final month absorbs the rounding remainder so the asset reaches exactly its salvage value', () async {
    // 100 / 3 months = 33.33 -> integer division gives 33/month, leaving
    // a 1-cent remainder that the 3rd month must absorb.
    final asset = await assets.create(
      businessId: businessId,
      name: 'Odd Asset',
      acquisitionDate: DateTime(2026, 1, 1),
      acquisitionCostMinorUnits: 100,
      usefulLifeMonths: 3,
      salvageValueMinorUnits: 0,
    );
    expect(asset.monthlyDepreciationMinorUnits, 33);

    await depreciation.postMonthlyDepreciation(fixedAssetUuid: asset.uuid, period: '2026-01', createdBy: user, deviceId: deviceId);
    await depreciation.postMonthlyDepreciation(fixedAssetUuid: asset.uuid, period: '2026-02', createdBy: user, deviceId: deviceId);
    final thirdMonth = await depreciation.postMonthlyDepreciation(
      fixedAssetUuid: asset.uuid,
      period: '2026-03',
      createdBy: user,
      deviceId: deviceId,
    );

    expect(thirdMonth.amountMinorUnits, 34); // 33 + 33 + 34 = 100
    expect(await assets.bookValue(asset), 0);

    expect(
      () => depreciation.postMonthlyDepreciation(fixedAssetUuid: asset.uuid, period: '2026-04', createdBy: user, deviceId: deviceId),
      throwsStateError, // fully depreciated — nothing left to post
    );
  });

  test('depreciation on an asset linked to an OperatingAsset tags the journal lines with that dimension', () async {
    final asset = await assets.create(
      businessId: businessId,
      name: 'Truck 01',
      operatingAssetUuid: 'vehicle-uuid-1',
      acquisitionDate: DateTime(2026, 1, 1),
      acquisitionCostMinorUnits: 600000,
      usefulLifeMonths: 6,
    );

    await depreciation.postMonthlyDepreciation(fixedAssetUuid: asset.uuid, period: '2026-01', createdBy: user, deviceId: deviceId);

    final vehicleLedger = await ledger.dimensionStatement(businessId: businessId, dimensionUuid: 'vehicle-uuid-1');
    expect(vehicleLedger.length, 2); // the expense line and the accumulated-depreciation line
  });
}
