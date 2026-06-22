import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late LedgerRepository ledger;

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
    ledger = LedgerRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('trialBalance only includes the requesting business, even when another '
      'business shares the same account code', () async {
    await seedChartOfAccounts(db, 'business-A');
    await seedChartOfAccounts(db, 'business-B'); // both seed accounts "1010", "4010", etc.

    await ledger.post(
      businessId: 'business-A',
      sourceType: 'Sale',
      sourceId: 'a-1',
      createdBy: 'tester',
      deviceId: 'd1',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 5000, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 5000),
      ],
    );

    // Business B posts a much larger amount to the *same* account code.
    await ledger.post(
      businessId: 'business-B',
      sourceType: 'Sale',
      sourceId: 'b-1',
      createdBy: 'tester',
      deviceId: 'd1',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 999999, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 999999),
      ],
    );

    final trialBalanceA = await ledger.trialBalance(businessId: 'business-A');
    final cashRowA = trialBalanceA.firstWhere((r) => r['code'] == '1010');

    expect(cashRowA['total_debit'], 5000); // must not include business-B's 999999
  });

  test('accountBalanceMinorUnits is also business-scoped under a shared account code', () async {
    await seedChartOfAccounts(db, 'business-A');
    await seedChartOfAccounts(db, 'business-B');

    await ledger.post(
      businessId: 'business-B',
      sourceType: 'Sale',
      sourceId: 'b-1',
      createdBy: 'tester',
      deviceId: 'd1',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 10000, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 10000),
      ],
    );

    final balanceA = await ledger.accountBalanceMinorUnits(businessId: 'business-A', accountCode: '1010');
    expect(balanceA, 0); // business-A has posted nothing — must not see business-B's cash
  });

  test('accountStatement returns chronological lines for the Cash Book view', () async {
    await seedChartOfAccounts(db, 'business-A');

    await ledger.post(
      businessId: 'business-A',
      sourceType: 'Payment',
      sourceId: 'p-1',
      createdBy: 'tester',
      deviceId: 'd1',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 2000, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '1030', debitMinorUnits: 0, creditMinorUnits: 2000),
      ],
    );

    final statement = await ledger.accountStatement(businessId: 'business-A', accountCode: '1010');
    expect(statement.length, 1);
    expect(statement.first['debit_minor_units'], 2000);
  });
}
