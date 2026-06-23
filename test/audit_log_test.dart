import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/system/audit_log_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late LedgerRepository ledger;
  late AuditLogRepository auditLog;
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
    auditLog = AuditLogRepository(db);
    ledger = LedgerRepository(db, null, auditLog);
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

  test('voiding writes an audit log entry', () async {
    final entry = await postCashSale();
    await ledger.void_(entry, voidedBy: 'owner', reason: 'test mistake');

    final logs = await auditLog.list(businessId: businessId);
    expect(logs.length, 1);
    expect(logs.first.action, 'void');
    expect(logs.first.entityId, entry.uuid);
    expect(logs.first.performedBy, 'owner');
    expect(logs.first.details, 'test mistake');
  });

  test('reversing writes an audit log entry', () async {
    final entry = await postCashSale();
    await ledger.reverse(entry, createdBy: 'owner', deviceId: 'device-1');

    final logs = await auditLog.list(businessId: businessId);
    expect(logs.length, 1);
    expect(logs.first.action, 'reverse');
    expect(logs.first.entityId, entry.uuid);
  });

  test('without an audit log wired in, void/reverse still work (it is opt-in)', () async {
    final ledgerNoAudit = LedgerRepository(db);
    final entry = await postCashSale();
    await ledgerNoAudit.void_(entry, voidedBy: 'owner', reason: 'no audit log configured');

    final logs = await auditLog.list(businessId: businessId);
    expect(logs, isEmpty);
  });
}
