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
    ledger = LedgerRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<JournalEntry> postCashSale() => ledger.post(
        businessId: businessId,
        sourceType: 'Sale',
        sourceId: 'sale-1',
        createdBy: 'tester',
        deviceId: 'device-1',
        rawLines: [
          JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 1000, creditMinorUnits: 0),
          JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 1000),
        ],
      );

  test('voiding an entry removes it from balances entirely, with no offsetting entry', () async {
    final entry = await postCashSale();

    await ledger.void_(entry, voidedBy: 'owner', reason: 'duplicate entry, caught same day');

    final cashBalance = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(cashBalance, 0);

    final allEntries = await db.query(JournalEntry.tableName);
    expect(allEntries.length, 1); // the row still exists — no hard delete
    expect(allEntries.first['status'], JournalEntryStatus.void_.name);
  });

  test('void requires a non-empty reason', () async {
    final entry = await postCashSale();
    expect(
      () => ledger.void_(entry, voidedBy: 'owner', reason: ''),
      throwsArgumentError,
    );
  });

  test('an already-reversed entry cannot also be voided', () async {
    final entry = await postCashSale();
    await ledger.reverse(entry, createdBy: 'owner', deviceId: 'device-1');

    final reloaded = await ledger.findByUuid(entry.uuid);
    expect(
      () => ledger.void_(reloaded!, voidedBy: 'owner', reason: 'test'),
      throwsStateError,
    );
  });

  test('a voided entry does not appear in the account statement (Cash Book) either', () async {
    final entry = await postCashSale();
    await ledger.void_(entry, voidedBy: 'owner', reason: 'mistake');

    final statement = await ledger.accountStatement(businessId: businessId, accountCode: '1010');
    expect(statement, isEmpty);
  });
}
