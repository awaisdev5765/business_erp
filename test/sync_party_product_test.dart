import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/sync/conflict_record_repository.dart';
import 'package:business_erp/core/sync/firestore_sync_service.dart';
import 'package:business_erp/core/sync/sync_queue_item.dart';
import 'package:business_erp/core/sync/sync_queue_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/features/spare_parts/inventory/product_repository.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late FakeFirebaseFirestore firestore;
  late SyncQueueRepository syncQueue;
  late FirestoreSyncService sync;
  late PartyRepository parties;
  late ProductRepository products;
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

    firestore = FakeFirebaseFirestore();
    syncQueue = SyncQueueRepository(db);
    parties = PartyRepository(db, syncQueue);
    products = ProductRepository(db, syncQueue);
    sync = FirestoreSyncService(
      db: db,
      firestore: firestore,
      syncQueue: syncQueue,
      ledger: LedgerRepository(db),
      conflictRecords: ConflictRecordRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('creating a Party enqueues it and uploadPending writes it to Firestore', () async {
    final party = await parties.create(businessId: businessId, type: PartyType.customer, name: 'Acme Co');

    final pendingBefore = await syncQueue.pending(businessId: businessId);
    expect(pendingBefore.any((i) => i.entityType == 'Party' && i.entityId == party.uuid), isTrue);

    final count = await sync.uploadPending(businessId);
    expect(count, 1);

    final doc = await firestore.collection('businesses').doc(businessId).collection('parties').doc(party.uuid).get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['name'], 'Acme Co');

    final pendingAfter = await syncQueue.pending(businessId: businessId);
    expect(pendingAfter, isEmpty);
  });

  test('creating a Product enqueues it and uploadPending writes it to Firestore', () async {
    final product = await products.create(
      businessId: businessId,
      sku: 'SKU-1',
      name: 'Brake Pad',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 1500,
    );

    final count = await sync.uploadPending(businessId);
    expect(count, 1);

    final doc = await firestore.collection('businesses').doc(businessId).collection('products').doc(product.uuid).get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['sku'], 'SKU-1');
  });

  test('without a sync queue, Party/Product creation enqueues nothing (opt-in)', () async {
    final noSyncParties = PartyRepository(db);
    await noSyncParties.create(businessId: businessId, type: PartyType.customer, name: 'No Sync Co');

    final pending = await syncQueue.pending(businessId: businessId);
    expect(pending, isEmpty);
  });

  test('a queue item for an unrecognized entity type is skipped, not marked failed or synced', () async {
    await syncQueue.enqueue(
      db,
      businessId: businessId,
      entityType: 'SomethingNotWiredUp',
      entityId: 'whatever',
      operation: SyncOperation.create,
    );

    final count = await sync.uploadPending(businessId);
    expect(count, 0);

    final stillPending = await syncQueue.pending(businessId: businessId);
    expect(stillPending.length, 1); // untouched, not failed
  });
}
