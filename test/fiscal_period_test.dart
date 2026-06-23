import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/fiscal_period.dart';
import 'package:business_erp/core/accounting/fiscal_period_repository.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late LedgerRepository ledgerWithoutPeriods;
  late LedgerRepository ledgerWithPeriods;
  late FiscalPeriodRepository periods;
  const businessId = 'business-1';

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
    periods = FiscalPeriodRepository(db);
    ledgerWithoutPeriods = LedgerRepository(db);
    ledgerWithPeriods = LedgerRepository(db, periods);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<JournalEntry> postCashSale(LedgerRepository ledger, DateTime date) => ledger.post(
        businessId: businessId,
        sourceType: 'Sale',
        sourceId: 'sale-${date.toIso8601String()}',
        createdBy: 'tester',
        deviceId: 'device-1',
        date: date,
        rawLines: [
          JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 1000, creditMinorUnits: 0),
          JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 1000),
        ],
      );

  test('posting with no fiscal periods configured is unaffected (opt-in behavior)', () async {
    await postCashSale(ledgerWithoutPeriods, DateTime(2026, 1, 15));
    final balance = await ledgerWithoutPeriods.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balance, 1000);
  });

  test('posting into a date with no period defined is allowed even when other periods exist', () async {
    await periods.create(businessId: businessId, startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 31));
    await postCashSale(ledgerWithPeriods, DateTime(2026, 2, 15)); // outside the Jan period
    final balance = await ledgerWithPeriods.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balance, 1000);
  });

  test('posting into an open period succeeds', () async {
    await periods.create(businessId: businessId, startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 31));
    await postCashSale(ledgerWithPeriods, DateTime(2026, 1, 15));
    final balance = await ledgerWithPeriods.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balance, 1000);
  });

  test('posting into a closed period is rejected', () async {
    final jan = await periods.create(businessId: businessId, startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 31));
    await periods.setStatus(jan.uuid, FiscalPeriodStatus.closed);

    expect(
      () => postCashSale(ledgerWithPeriods, DateTime(2026, 1, 15)),
      throwsStateError,
    );

    final balance = await ledgerWithPeriods.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balance, 0); // rejected — nothing should have been posted
  });

  test('posting into a locked period is rejected the same as closed', () async {
    final jan = await periods.create(businessId: businessId, startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 31));
    await periods.setStatus(jan.uuid, FiscalPeriodStatus.locked);

    expect(
      () => postCashSale(ledgerWithPeriods, DateTime(2026, 1, 15)),
      throwsStateError,
    );
  });

  test('reversing a posted entry from a since-closed period succeeds (reversal is dated now, not back-dated)', () async {
    final jan = await periods.create(businessId: businessId, startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 31));
    final entry = await postCashSale(ledgerWithPeriods, DateTime(2026, 1, 15));
    await periods.setStatus(jan.uuid, FiscalPeriodStatus.closed);

    // Should not throw: reverse() defaults the reversal's date to
    // DateTime.now(), which falls outside the now-closed January period.
    await ledgerWithPeriods.reverse(entry, createdBy: 'tester', deviceId: 'device-1');

    final balance = await ledgerWithPeriods.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balance, 0); // original + reversal net to zero
  });
}
