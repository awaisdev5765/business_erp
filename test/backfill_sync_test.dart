import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/ledger_repository.dart';
import 'package:business_erp/core/party/party.dart';
import 'package:business_erp/core/party/party_repository.dart';
import 'package:business_erp/core/sync/conflict_record_repository.dart';
import 'package:business_erp/core/sync/firestore_sync_service.dart';
import 'package:business_erp/core/sync/sync_queue_repository.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/system/number_sequence_service.dart';
import 'package:business_erp/core/tenant/business.dart';
import 'package:business_erp/core/tenant/business_repository.dart';
import 'package:business_erp/features/spare_parts/inventory/product_repository.dart';
import 'package:business_erp/features/spare_parts/sales/sale.dart';
import 'package:business_erp/features/spare_parts/sales/sale_repository.dart';

/// Simulates exactly the scenario the user asked about: a business
/// created (and used) *before* this device's app build had any sync
/// wiring for Business/Sale/StockMovement at all — every repository here
/// is built with no SyncQueueRepository, the same as the app's very
/// first releases. backfillSyncQueue() should notice all of that
/// untracked data once sync coverage exists and enqueue it, so it
/// becomes recoverable going forward even though it predates the fix.
void main() {
  late Directory tempDirA;
  late Directory tempDirB;
  late Database dbA;
  late Database dbB;
  late FakeFirebaseFirestore firestore;
  const user = 'tester';
  const deviceId = 'device-1';

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
    firestore = FakeFirebaseFirestore();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
    await tempDirA.delete(recursive: true);
    await tempDirB.delete(recursive: true);
  });

  test('backfillSyncQueue picks up pre-existing local data that predates sync coverage, making it recoverable', () async {
    // No SyncQueueRepository passed anywhere here — this is "the old
    // app build," before Business/Sale/StockMovement ever enqueued
    // themselves.
    final ledgerA = LedgerRepository(dbA);
    final businessesA = BusinessRepository(dbA);
    final partiesA = PartyRepository(dbA);
    final productsA = ProductRepository(dbA);
    final numberingA = NumberSequenceService(dbA);
    final salesA = SaleRepository(dbA, ledgerA, productsA, numberingA);

    final business = await businessesA.create(name: 'Legacy Shop', type: BusinessType.sparePartsShop);
    final customer = await partiesA.create(businessId: business.uuid, type: PartyType.customer, name: 'Old Customer');
    final product = await productsA.create(
      businessId: business.uuid, sku: 'OLD-1', name: 'Legacy Widget',
      costPriceMinorUnits: 100, salePriceMinorUnits: 200, openingStock: 20,
    );
    final sale = await salesA.create(
      businessId: business.uuid, customerUuid: customer.uuid, paymentMethod: PaymentMethod.credit,
      createdBy: user, deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 3, unitPriceMinorUnits: 200)],
    );

    // Nothing was ever enqueued for any of this.
    final syncQueueA = SyncQueueRepository(dbA);
    expect(await syncQueueA.all(businessId: business.uuid), isEmpty);

    // The app is upgraded: sync wiring now exists, and the periodic
    // background sync (syncAll) runs for the first time this session.
    final syncA = FirestoreSyncService(
      db: dbA, firestore: firestore, syncQueue: syncQueueA, ledger: ledgerA,
      conflictRecords: ConflictRecordRepository(dbA), numbering: numberingA,
    );
    await syncA.syncAll(business.uuid);

    final queueItemsAfterSync = await syncQueueA.all(businessId: business.uuid);
    expect(queueItemsAfterSync, isNotEmpty);
    expect(queueItemsAfterSync.every((i) => i.status.name == 'synced'), true);

    // Calling syncAll again shouldn't re-enqueue (or re-upload) anything
    // already tracked — backfill only catches genuinely never-tracked rows.
    final countBefore = queueItemsAfterSync.length;
    await syncA.syncAll(business.uuid);
    expect(await syncQueueA.all(businessId: business.uuid), hasLength(countBefore));

    // --- Device B: proves the backfilled data is now actually
    // recoverable, not just enqueued.
    final syncQueueB = SyncQueueRepository(dbB);
    final ledgerB = LedgerRepository(dbB, null, null, syncQueueB);
    final syncB = FirestoreSyncService(
      db: dbB, firestore: firestore, syncQueue: syncQueueB, ledger: ledgerB,
      conflictRecords: ConflictRecordRepository(dbB), numbering: NumberSequenceService(dbB),
    );

    final restored = await syncB.restoreFromCloud(isSuperAdmin: true, businessAccess: const {});
    expect(restored, true);

    expect((await dbB.query(Business.tableName)).single['name'], 'Legacy Shop');
    expect((await dbB.query(Party.tableName)).single['name'], 'Old Customer');
    final restoredProducts = await dbB.query('products', where: 'business_id = ?', whereArgs: [business.uuid]);
    expect(restoredProducts.single['name'], 'Legacy Widget');
    final restoredSales = await dbB.query('sales', where: 'business_id = ?', whereArgs: [business.uuid]);
    expect(restoredSales.single['uuid'], sale.uuid);
    final restoredMovements = await dbB.query('stock_movements', where: 'business_id = ?', whereArgs: [business.uuid]);
    expect(restoredMovements, isNotEmpty); // the sale's stock decrement was backfilled too
  });
}
