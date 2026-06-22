import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/account.dart';
import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/tenant/business.dart';

void main() {
  late Database db;
  late Directory tempDir;
  const businessId = 'business-1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sqlite_test_');
    db = await databaseFactory.openDatabase(
      '${tempDir.path}/test.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(Business.createTableSql);
          await db.execute(Account.createTableSql);
          await db.execute(Account.createIndexSql);
          await db.execute(JournalEntry.createTableSql);
          await db.execute(JournalEntry.createIndexSql);
          await db.execute(JournalEntry.createStatusIndexSql);
          await db.execute(JournalLine.createTableSql);
          await db.execute(JournalLine.createIndexSql);
          await db.execute(JournalLine.createEntryIndexSql);
        },
      ),
    );
    await seedChartOfAccounts(db, businessId);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('cash sale posts a balanced entry and updates Cash + Sales Income balances', () async {
    final ledger = LedgerRepository(db);

    // 100.00 cash sale: Dr Cash 1010, Cr Sales Income 4010.
    await ledger.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-1',
      createdBy: 'tester',
      deviceId: 'device-1',
      rawLines: [
        JournalLine(
          entryUuid: '',
          accountCode: '1010',
          debitMinorUnits: 10000,
          creditMinorUnits: 0,
        ),
        JournalLine(
          entryUuid: '',
          accountCode: '4010',
          debitMinorUnits: 0,
          creditMinorUnits: 10000,
        ),
      ],
    );

    final cashBalance = await ledger.accountBalanceMinorUnits(
      businessId: businessId,
      accountCode: '1010',
    );
    final salesBalance = await ledger.accountBalanceMinorUnits(
      businessId: businessId,
      accountCode: '4010',
    );

    expect(cashBalance, 10000); // Dr balance: cash increased
    expect(salesBalance, -10000); // Cr balance: income accounts are negative under Dr-Cr convention
  });

  test('unbalanced entry is rejected', () async {
    final ledger = LedgerRepository(db);

    expect(
      () => ledger.post(
        businessId: businessId,
        sourceType: 'Sale',
        sourceId: 'sale-2',
        createdBy: 'tester',
        deviceId: 'device-1',
        rawLines: [
          JournalLine(
            entryUuid: '',
            accountCode: '1010',
            debitMinorUnits: 5000,
            creditMinorUnits: 0,
          ),
          JournalLine(
            entryUuid: '',
            accountCode: '4010',
            debitMinorUnits: 0,
            creditMinorUnits: 4000,
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('reversal appends an offsetting entry without mutating the original lines', () async {
    final ledger = LedgerRepository(db);

    final entry = await ledger.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-3',
      createdBy: 'tester',
      deviceId: 'device-1',
      rawLines: [
        JournalLine(
          entryUuid: '',
          accountCode: '1010',
          debitMinorUnits: 2000,
          creditMinorUnits: 0,
        ),
        JournalLine(
          entryUuid: '',
          accountCode: '4010',
          debitMinorUnits: 0,
          creditMinorUnits: 2000,
        ),
      ],
    );

    await ledger.reverse(entry, createdBy: 'tester', deviceId: 'device-1');

    final cashBalance = await ledger.accountBalanceMinorUnits(
      businessId: businessId,
      accountCode: '1010',
    );

    expect(cashBalance, 0); // original + reversal net to zero

    final allEntries = await db.query(JournalEntry.tableName);
    expect(allEntries.length, 2); // both rows still exist — no hard deletes/mutation
  });
}
