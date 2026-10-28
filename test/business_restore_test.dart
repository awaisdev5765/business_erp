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
import 'package:business_erp/features/spare_parts/sales/refund_repository.dart';
import 'package:business_erp/features/spare_parts/sales/sale.dart';
import 'package:business_erp/features/spare_parts/sales/sale_repository.dart';

/// Simulates exactly the bug report this exists to fix: a business is
/// created and used on one device ("browser tab A"), then a second,
/// completely empty local database stands in for the same browser
/// closed and reopened with sqflite_common_ffi_web's experimental
/// IndexedDB persistence having lost everything. restoreFromCloud()
/// should bring the business, its party/product, and its (partially
/// refunded) sale back without the user recreating anything.
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

  test('restoreFromCloud recreates a business and its data on a device whose local storage was wiped', () async {
    // --- Device A: create a business, a customer, a product, a credit
    // sale, and a partial refund of it — exactly "create business and do
    // something in it."
    final syncQueueA = SyncQueueRepository(dbA);
    final ledgerA = LedgerRepository(dbA, null, null, syncQueueA);
    final businessesA = BusinessRepository(dbA, syncQueueA);
    final partiesA = PartyRepository(dbA, syncQueueA);
    final productsA = ProductRepository(dbA, syncQueueA);
    final numberingA = NumberSequenceService(dbA);
    final salesA = SaleRepository(dbA, ledgerA, productsA, numberingA, null, null, syncQueueA);
    final refundsA = RefundRepository(dbA, ledgerA, productsA, salesA, numberingA, null, syncQueueA);
    final syncA = FirestoreSyncService(
      db: dbA,
      firestore: firestore,
      syncQueue: syncQueueA,
      ledger: ledgerA,
      conflictRecords: ConflictRecordRepository(dbA),
    );

    final business = await businessesA.create(name: 'Test Spares Co', type: BusinessType.sparePartsShop, baseCurrency: 'USD');
    final customer = await partiesA.create(businessId: business.uuid, type: PartyType.customer, name: 'A Customer');
    final product = await productsA.create(
      businessId: business.uuid,
      sku: 'BRK-001',
      name: 'Brake Pad',
      costPriceMinorUnits: 1000,
      salePriceMinorUnits: 1500,
      openingStock: 10,
    );
    final sale = await salesA.create(
      businessId: business.uuid,
      customerUuid: customer.uuid,
      paymentMethod: PaymentMethod.credit,
      createdBy: user,
      deviceId: deviceId,
      lineInputs: [SaleLineInput(productUuid: product.uuid, quantity: 4, unitPriceMinorUnits: 1500)],
    );
    final saleLineId = (await refundsA.refundableLines(sale.uuid)).first.line.id!;
    await refundsA.refund(
      saleUuid: sale.uuid,
      lines: [RefundLineInput(saleLineId: saleLineId, quantity: 1)],
      refundedBy: user,
      deviceId: deviceId,
    );

    await syncA.uploadPending(business.uuid);

    // --- Device B: a brand new, empty local database — what's left
    // after the browser tab loses its IndexedDB-backed SQLite file.
    final syncQueueB = SyncQueueRepository(dbB);
    final ledgerB = LedgerRepository(dbB, null, null, syncQueueB);
    final syncB = FirestoreSyncService(
      db: dbB,
      firestore: firestore,
      syncQueue: syncQueueB,
      ledger: ledgerB,
      conflictRecords: ConflictRecordRepository(dbB),
    );

    final beforeRestore = await dbB.query(Business.tableName);
    expect(beforeRestore, isEmpty);

    final restored = await syncB.restoreFromCloud(isSuperAdmin: true, businessAccess: const {});
    expect(restored, true);

    final businessRows = await dbB.query(Business.tableName, where: 'uuid = ?', whereArgs: [business.uuid]);
    expect(businessRows.single['name'], 'Test Spares Co');

    final partyRows = await dbB.query(Party.tableName, where: 'uuid = ?', whereArgs: [customer.uuid]);
    expect(partyRows.single['name'], 'A Customer');

    final businessesB = BusinessRepository(dbB);
    final productsB = ProductRepository(dbB);
    final salesB = SaleRepository(dbB, ledgerB, productsB, NumberSequenceService(dbB));
    final refundsB = RefundRepository(dbB, ledgerB, productsB, salesB, NumberSequenceService(dbB));

    expect((await businessesB.findByUuid(business.uuid))!.name, 'Test Spares Co');
    expect((await productsB.findByUuid(product.uuid))!.name, 'Brake Pad');

    final restoredSale = await salesB.findByUuid(sale.uuid);
    expect(restoredSale, isNotNull);
    expect(restoredSale!.lines.single.quantity, 4);
    expect(restoredSale.status, SaleStatus.partiallyReturned);

    // The critical correctness check: the restored RefundLine's
    // saleLineId must still point at the restored SaleLine (ids are
    // round-tripped explicitly, not reassigned), so refundableLines()
    // correctly reports 3 left (4 sold - 1 already refunded), not 4.
    final refundable = await refundsB.refundableLines(sale.uuid);
    expect(refundable.single.refundableQty, 3);

    // The ledger itself restored too (via the existing downloadAndMerge),
    // so the customer's receivable reflects the sale net of the refund.
    final receivable = await ledgerB.accountBalanceMinorUnits(businessId: business.uuid, accountCode: '1030');
    expect(receivable, 4 * 1500 - 1 * 1500);
  });

  test('restoreFromCloud is a no-op for a user with no accessible businesses', () async {
    final syncQueueB = SyncQueueRepository(dbB);
    final ledgerB = LedgerRepository(dbB, null, null, syncQueueB);
    final syncB = FirestoreSyncService(
      db: dbB,
      firestore: firestore,
      syncQueue: syncQueueB,
      ledger: ledgerB,
      conflictRecords: ConflictRecordRepository(dbB),
    );

    final restored = await syncB.restoreFromCloud(isSuperAdmin: false, businessAccess: const {});
    expect(restored, false);
    expect(await dbB.query(Business.tableName), isEmpty);
  });
}
