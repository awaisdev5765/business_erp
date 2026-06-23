import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/journal_entry.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/sync/conflict_record_repository.dart';
import 'package:business_erp/core/sync/firestore_sync_service.dart';
import 'package:business_erp/core/sync/sync_queue_repository.dart';
import 'package:business_erp/core/system/database.dart';

/// Simulates two devices sharing one backend: each gets its own local
/// SQLite database (its own LedgerRepository/SyncQueueRepository), but
/// both sync services share one FakeFirebaseFirestore instance, standing
/// in for the real shared project. This is the multi-device QA pass
/// PHASES.md Phase 5 calls for, made possible without a live Firebase
/// project or emulator.
void main() {
  late Directory tempDirA;
  late Directory tempDirB;
  late Database dbA;
  late Database dbB;
  late FakeFirebaseFirestore firestore;
  late LedgerRepository ledgerA;
  late LedgerRepository ledgerB;
  late FirestoreSyncService syncA;
  late FirestoreSyncService syncB;
  const businessId = 'business-1';
  const user = 'tester';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirA = await Directory.systemTemp.createTemp('device_a_');
    tempDirB = await Directory.systemTemp.createTemp('device_b_');
    dbA = await databaseFactory.openDatabase(
      '${tempDirA.path}/test.db',
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
    );
    dbB = await databaseFactory.openDatabase(
      '${tempDirB.path}/test.db',
      options: OpenDatabaseOptions(version: 1, onCreate: (db, version) => createSchema(db)),
    );
    await seedChartOfAccounts(dbA, businessId);
    await seedChartOfAccounts(dbB, businessId);

    firestore = FakeFirebaseFirestore();

    final syncQueueA = SyncQueueRepository(dbA);
    final syncQueueB = SyncQueueRepository(dbB);
    final conflictRecordsA = ConflictRecordRepository(dbA);
    final conflictRecordsB = ConflictRecordRepository(dbB);

    ledgerA = LedgerRepository(dbA, null, null, syncQueueA);
    ledgerB = LedgerRepository(dbB, null, null, syncQueueB);

    syncA = FirestoreSyncService(
      db: dbA, firestore: firestore, syncQueue: syncQueueA, ledger: ledgerA, conflictRecords: conflictRecordsA,
    );
    syncB = FirestoreSyncService(
      db: dbB, firestore: firestore, syncQueue: syncQueueB, ledger: ledgerB, conflictRecords: conflictRecordsB,
    );
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
    await tempDirA.delete(recursive: true);
    await tempDirB.delete(recursive: true);
  });

  test('an entry posted on device A reaches device B via upload then download', () async {
    final entry = await ledgerA.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-1',
      createdBy: user,
      deviceId: 'device-A',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 1000, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 1000),
      ],
    );

    await syncA.uploadPending(businessId);

    final beforeDownload = await dbB.query(JournalEntry.tableName);
    expect(beforeDownload, isEmpty); // device B hasn't pulled yet

    final result = await syncB.downloadAndMerge(businessId);
    expect(result.inserted, 1);
    expect(result.conflicts, 0);

    final found = await ledgerB.findByUuid(entry.uuid);
    expect(found, isNotNull);
    expect(found!.lines.length, 2);

    final balanceOnB = await ledgerB.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    expect(balanceOnB, 1000);
  });

  test('device A voiding an entry propagates to device B as a safe status adoption (no conflict)', () async {
    final entry = await ledgerA.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-1',
      createdBy: user,
      deviceId: 'device-A',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 1000, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 1000),
      ],
    );
    await syncA.uploadPending(businessId);
    await syncB.downloadAndMerge(businessId); // B now has it as posted, untouched

    await ledgerA.void_(entry, voidedBy: user, reason: 'mistake');
    await syncA.uploadPending(businessId); // pushes the status update to Firestore

    final result = await syncB.downloadAndMerge(businessId);
    expect(result.statusUpdated, 1);
    expect(result.conflicts, 0);

    final foundOnB = await ledgerB.findByUuid(entry.uuid);
    expect(foundOnB!.status, JournalEntryStatus.void_);
  });

  test('two devices independently transitioning the same entry differently is recorded as a real conflict', () async {
    final entry = await ledgerA.post(
      businessId: businessId,
      sourceType: 'Sale',
      sourceId: 'sale-1',
      createdBy: user,
      deviceId: 'device-A',
      rawLines: [
        JournalLine(entryUuid: '', accountCode: '1010', debitMinorUnits: 1000, creditMinorUnits: 0),
        JournalLine(entryUuid: '', accountCode: '4010', debitMinorUnits: 0, creditMinorUnits: 1000),
      ],
    );
    await syncA.uploadPending(businessId);
    await syncB.downloadAndMerge(businessId); // both devices now have it as posted

    // Device B reverses it and uploads first.
    final entryOnB = await ledgerB.findByUuid(entry.uuid);
    await ledgerB.reverse(entryOnB!, createdBy: user, deviceId: 'device-B');
    await syncB.uploadPending(businessId);

    // Device A, unaware of B's reversal, independently voids its own
    // copy and uploads — overwriting Firestore's status.
    await ledgerA.void_(entry, voidedBy: user, reason: 'mistake');
    await syncA.uploadPending(businessId);

    // Device B downloads: remote is now 'void_', but B's local copy is
    // already 'reversed' (a different terminal status) — a genuine
    // conflict, not a safe adoption.
    final result = await syncB.downloadAndMerge(businessId);
    expect(result.conflicts, 1);
    expect(result.statusUpdated, 0);

    final conflictRecordsB = ConflictRecordRepository(dbB);
    final unresolved = await conflictRecordsB.unresolved(businessId: businessId);
    expect(unresolved.length, 1);
    expect(unresolved.first.entityId, entry.uuid);

    // B's local status is left untouched, not silently overwritten.
    final stillOnB = await ledgerB.findByUuid(entry.uuid);
    expect(stillOnB!.status, JournalEntryStatus.reversed);
  });
}
