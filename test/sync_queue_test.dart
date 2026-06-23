import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/sync/sync_queue_item.dart';
import 'package:business_erp/core/sync/sync_queue_repository.dart';
import 'package:business_erp/core/system/database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late SyncQueueRepository syncQueue;
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
    syncQueue = SyncQueueRepository(db);
    ledger = LedgerRepository(db, null, null, syncQueue);
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

  test('posting a journal entry enqueues exactly one sync item, atomically with the post', () async {
    final entry = await postCashSale();

    final pending = await syncQueue.pending(businessId: businessId);
    expect(pending.length, 1);
    expect(pending.first.entityType, 'JournalEntry');
    expect(pending.first.entityId, entry.uuid);
    expect(pending.first.operation, SyncOperation.create);
    expect(pending.first.status, SyncQueueStatus.pending);
  });

  test('without a sync queue wired in, posting still works and enqueues nothing (opt-in)', () async {
    final ledgerNoSync = LedgerRepository(db);
    await ledgerNoSync.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-2',
      createdBy: 'tester',
      deviceId: 'device-1',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 500, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 500),
      ],
    );

    final pending = await syncQueue.pending(businessId: businessId);
    expect(pending, isEmpty);
  });

  test('reversing enqueues the original create, the reversal create, and the original update', () async {
    final entry = await postCashSale();
    await ledger.reverse(entry, createdBy: 'tester', deviceId: 'device-1');

    final all = await syncQueue.all(businessId: businessId);
    expect(all.length, 3);

    final updateForOriginal = all.where((i) => i.entityId == entry.uuid && i.operation == SyncOperation.update);
    expect(updateForOriginal.length, 1);
  });

  test('markSynced/markFailed transition status and pendingCount reflects only pending+failed', () async {
    final entry1 = await postCashSale();
    await ledger.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-3',
      createdBy: 'tester',
      deviceId: 'device-1',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 200, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 200),
      ],
    );

    final pendingBefore = await syncQueue.pending(businessId: businessId);
    expect(pendingBefore.length, 2);

    final firstItem = pendingBefore.firstWhere((i) => i.entityId == entry1.uuid);
    await syncQueue.markSynced(firstItem.id);

    final pendingAfter = await syncQueue.pending(businessId: businessId);
    expect(pendingAfter.length, 1);
    expect(await syncQueue.pendingCount(businessId: businessId), 1);

    await syncQueue.markFailed(pendingAfter.first.id, 'network error');
    final afterFail = await syncQueue.all(businessId: businessId);
    final failedItem = afterFail.firstWhere((i) => i.id == pendingAfter.first.id);
    expect(failedItem.status, SyncQueueStatus.failed);
    expect(failedItem.attempts, 1);
    expect(failedItem.lastError, 'network error');
    // failed items still count as pending work:
    expect(await syncQueue.pendingCount(businessId: businessId), 1);
  });
}
