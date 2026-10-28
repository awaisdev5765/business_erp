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
import 'package:business_erp/features/transport/contract_repository.dart';
import 'package:business_erp/features/transport/monthly_settlement_repository.dart';
import 'package:business_erp/features/transport/trip_income.dart';
import 'package:business_erp/features/transport/trip_income_repository.dart';
import 'package:business_erp/features/transport/vehicle_khata_line.dart';
import 'package:business_erp/features/transport/vehicle_khata_repository.dart';
import 'package:business_erp/features/transport/vehicle_profitability_service.dart';
import 'package:business_erp/features/transport/weight_entry_repository.dart';

void main() {
  late Database db;
  late Directory tempDir;
  const businessId = 'business-1';
  const deviceId = 'device-1';
  const user = 'tester';

  late LedgerRepository ledger;
  late OperatingAssetRepository assets;
  late PartyRepository parties;
  late ContractRepository contracts;
  late WeightEntryRepository weightEntries;
  late VehicleKhataRepository khata;
  late MonthlySettlementRepository settlements;
  late VehicleProfitabilityService vehicleProfitability;

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
    final trips = TripRepository(db);
    parties = PartyRepository(db);
    contracts = ContractRepository(db);
    weightEntries = WeightEntryRepository(db);
    khata = VehicleKhataRepository(db, ledger);
    settlements = MonthlySettlementRepository(db, ledger, weightEntries, khata);
    final tripIncomes = TripIncomeRepository(db, ledger, trips);
    vehicleProfitability = VehicleProfitabilityService(tripIncomes, khata);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('company bills stay a log; month hisaab + gari khata match the Excel books', () async {
    final truck1 = await assets.create(
      businessId: businessId,
      type: OperatingAssetType.vehicle,
      name: 'C-2319',
      registrationNumber: 'C-2319',
    );
    final truck2 = await assets.create(
      businessId: businessId,
      type: OperatingAssetType.vehicle,
      name: 'TTA-598',
      registrationNumber: 'TTA-598',
    );
    final company = await parties.create(businessId: businessId, type: PartyType.customer, name: 'A & S Oil Mills');
    await contracts.create(
      businessId: businessId,
      customerUuid: company.uuid,
      description: 'A & S Oil Mills',
      ratePerTonMinorUnits: 250000, // Rs 2,500 / ton
    );

    await weightEntries.create(
      businessId: businessId,
      vehicleUuid: truck1.uuid,
      companyUuid: company.uuid,
      weightKg: 10000,
      date: DateTime(2026, 3, 2),
    );
    await weightEntries.create(
      businessId: businessId,
      vehicleUuid: truck1.uuid,
      companyUuid: company.uuid,
      weightKg: 12500,
      date: DateTime(2026, 3, 10),
    );
    await weightEntries.create(
      businessId: businessId,
      vehicleUuid: truck2.uuid,
      companyUuid: company.uuid,
      weightKg: 8000,
      date: DateTime(2026, 3, 18),
    );

    expect(await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '4020'), 0);
    expect(await parties.outstandingBalanceMinorUnits(company.uuid), 0);

    await khata.setOpening(businessId: businessId, vehicleUuid: truck1.uuid, amountMinorUnits: 215543300);
    await khata.addKharcha(
      businessId: businessId,
      vehicleUuid: truck1.uuid,
      tafseel: 'Local Kharcha',
      amountMinorUnits: 400000,
      createdBy: user,
      deviceId: deviceId,
      date: DateTime(2026, 8, 3),
    );
    await khata.addKharcha(
      businessId: businessId,
      vehicleUuid: truck1.uuid,
      tafseel: 'Peshgi di',
      amountMinorUnits: 7000000,
      createdBy: user,
      deviceId: deviceId,
      date: DateTime(2026, 8, 4),
    );

    final beforeSettle = await khata.statement(truck1.uuid);
    expect(beforeSettle.last.runningBalanceMinorUnits, 215543300 - 400000 - 7000000);

    var truck1Profit = await vehicleProfitability.forAsset(truck1.uuid);
    expect(truck1Profit.revenueMinorUnits, 0);
    expect(truck1Profit.expenseMinorUnits, 7400000);

    final settlement = await settlements.settle(
      businessId: businessId,
      companyUuid: company.uuid,
      year: 2026,
      month: 3,
      ratePerTonMinorUnits: 250000,
      createdBy: user,
      deviceId: deviceId,
      companyName: 'A & S Oil Mills',
    );

    // 10,000 + 12,500 + 8,000 kg = 30.5 ton × 2,500 = 76,250
    expect(settlement.totalWeightKg, 30500);
    expect(settlement.amountMinorUnits, 7625000);
    expect(await parties.outstandingBalanceMinorUnits(company.uuid), 7625000);

    truck1Profit = await vehicleProfitability.forAsset(truck1.uuid);
    expect(truck1Profit.revenueMinorUnits, 5625000); // 22.5 ton × 2500
    expect(truck1Profit.expenseMinorUnits, 7400000);

    final truck1Sheet = await khata.statement(truck1.uuid);
    final billJama = truck1Sheet.map((r) => r.line).firstWhere((l) => l.sourceType == 'MonthlySettlement');
    expect(billJama.kind, VehicleKhataKind.jama);
    expect(billJama.tafseel, contains('A & S Oil Mills'));
    expect(billJama.jamaMinorUnits, 5625000);

    final truck2Sheet = await khata.statement(truck2.uuid);
    expect(truck2Sheet.single.line.jamaMinorUnits, 2000000);

    expect(
      () => settlements.settle(
        businessId: businessId,
        companyUuid: company.uuid,
        year: 2026,
        month: 3,
        ratePerTonMinorUnits: 250000,
        createdBy: user,
        deviceId: deviceId,
      ),
      throwsStateError,
    );
  });

  test('month hisaab without pending weight is rejected', () async {
    final company = await parties.create(businessId: businessId, type: PartyType.customer, name: 'No Loads Co');
    expect(
      () => settlements.settle(
        businessId: businessId,
        companyUuid: company.uuid,
        year: 2026,
        month: 4,
        ratePerTonMinorUnits: 100000,
        createdBy: user,
        deviceId: deviceId,
      ),
      throwsStateError,
    );
  });

  test('credit trip income still requires a customer (legacy)', () async {
    final vehicle = await assets.create(businessId: businessId, type: OperatingAssetType.vehicle, name: 'Truck 01');
    final trips = TripRepository(db);
    final tripIncomes = TripIncomeRepository(db, ledger, trips);
    final trip = await trips.create(
      businessId: businessId,
      tripType: TripType.transport,
      assetUuid: vehicle.uuid,
    );

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

  test('unsettled weight bill can be edited and deleted', () async {
    final company = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Edit Co');
    final truck = await assets.create(
      businessId: businessId,
      type: OperatingAssetType.vehicle,
      name: 'Edit Truck',
      registrationNumber: 'ED-1',
    );
    final entry = await weightEntries.create(
      businessId: businessId,
      vehicleUuid: truck.uuid,
      companyUuid: company.uuid,
      weightKg: 10000,
      date: DateTime(2026, 5, 1),
    );

    final updated = await weightEntries.update(
      uuid: entry.uuid,
      vehicleUuid: truck.uuid,
      companyUuid: company.uuid,
      weightKg: 12000,
      date: DateTime(2026, 5, 2),
    );
    expect(updated.weightKg, 12000);
    expect(updated.date, DateTime(2026, 5, 2));

    await weightEntries.delete(entry.uuid);
    expect(await weightEntries.findByUuid(entry.uuid), isNull);
  });

  test('settled weight bill is locked; manual khata can edit/delete', () async {
    final company = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Lock Co');
    final truck = await assets.create(
      businessId: businessId,
      type: OperatingAssetType.vehicle,
      name: 'Lock Truck',
      registrationNumber: 'LK-1',
    );
    final entry = await weightEntries.create(
      businessId: businessId,
      vehicleUuid: truck.uuid,
      companyUuid: company.uuid,
      weightKg: 10000,
      date: DateTime(2026, 6, 1),
    );
    await settlements.settle(
      businessId: businessId,
      companyUuid: company.uuid,
      year: 2026,
      month: 6,
      ratePerTonMinorUnits: 100000,
      createdBy: user,
      deviceId: deviceId,
      companyName: 'Lock Co',
    );

    expect(
      () => weightEntries.update(
        uuid: entry.uuid,
        vehicleUuid: truck.uuid,
        companyUuid: company.uuid,
        weightKg: 9000,
        date: DateTime(2026, 6, 1),
      ),
      throwsStateError,
    );
    expect(() => weightEntries.delete(entry.uuid), throwsStateError);

    final kharcha = await khata.addKharcha(
      businessId: businessId,
      vehicleUuid: truck.uuid,
      tafseel: 'Diesel',
      amountMinorUnits: 500000,
      createdBy: user,
      deviceId: deviceId,
      date: DateTime(2026, 6, 10),
    );
    final edited = await khata.updateManual(
      uuid: kharcha.uuid,
      tafseel: 'Diesel + oil',
      amountMinorUnits: 600000,
      date: DateTime(2026, 6, 11),
      createdBy: user,
      deviceId: deviceId,
    );
    expect(edited.tafseel, 'Diesel + oil');
    expect(edited.kharchaMinorUnits, 600000);

    final settlementJama = (await khata.statement(truck.uuid))
        .map((r) => r.line)
        .firstWhere((l) => l.sourceType == 'MonthlySettlement');
    expect(
      () => khata.deleteManual(uuid: settlementJama.uuid, deletedBy: user),
      throwsStateError,
    );

    await khata.deleteManual(uuid: kharcha.uuid, deletedBy: user);
    expect(await khata.findByUuid(kharcha.uuid), isNull);
  });
}
