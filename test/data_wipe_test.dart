import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:business_erp/core/accounting/chart_of_accounts_seed.dart';
import 'package:business_erp/core/system/data_wipe_service.dart';
import 'package:business_erp/core/system/database.dart';
import 'package:business_erp/core/tenant/business.dart';
import 'package:business_erp/core/tenant/business_repository.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late FakeFirebaseFirestore firestore;
  late DataWipeService wipeService;
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
    wipeService = DataWipeService(db, firestore);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('wipeLocalDatabase drops every table and recreates an empty schema', () async {
    final businesses = BusinessRepository(db);
    await businesses.create(name: 'My Shop', type: BusinessType.sparePartsShop);
    expect((await businesses.list()).length, 1);

    await wipeService.wipeLocalDatabase();

    // Schema still works (createSchema() ran again) and is empty.
    final afterWipe = BusinessRepository(db);
    expect(await afterWipe.list(), isEmpty);

    // Accounts table also empty — seedChartOfAccounts was never re-run.
    final accountRows = await db.query('accounts');
    expect(accountRows, isEmpty);
  });

  test('wipeFirestoreData deletes every business doc and its subcollections', () async {
    await firestore.collection('businesses').doc(businessId).set({'name': 'My Shop'});
    await firestore.collection('businesses').doc(businessId).collection('parties').doc('p1').set({'name': 'Acme'});
    await firestore.collection('businesses').doc(businessId).collection('products').doc('prod1').set({'sku': 'A1'});
    await firestore.collection('businesses').doc(businessId).collection('weightEntries').doc('w1').set({'weightKg': 1000});
    await firestore.collection('businesses').doc(businessId).collection('vehicleKhataLines').doc('k1').set({'tafseel': 'Local'});
    await firestore.collection('businesses').doc(businessId).collection('sales').doc('s1').set({'total': 1});

    await wipeService.wipeFirestoreData();

    final businessDoc = await firestore.collection('businesses').doc(businessId).get();
    expect(businessDoc.exists, isFalse);

    final parties = await firestore.collection('businesses').doc(businessId).collection('parties').get();
    expect(parties.docs, isEmpty);
    final weights = await firestore.collection('businesses').doc(businessId).collection('weightEntries').get();
    expect(weights.docs, isEmpty);
    final khata = await firestore.collection('businesses').doc(businessId).collection('vehicleKhataLines').get();
    expect(khata.docs, isEmpty);
    final sales = await firestore.collection('businesses').doc(businessId).collection('sales').get();
    expect(sales.docs, isEmpty);
  });

  test('wipeFirestoreData strips staff businessAccess but leaves the Super Admin profile untouched', () async {
    await firestore.collection('users').doc('super-uid').set({
      'uid': 'super-uid',
      'email': 'superadmin@berp.com',
      'isSuperAdmin': true,
      'businessAccess': {'business-1': 'businessAdmin'},
    });
    await firestore.collection('users').doc('staff-uid').set({
      'uid': 'staff-uid',
      'email': 'cashier@example.com',
      'isSuperAdmin': false,
      'businessAccess': {'business-1': 'cashier'},
    });

    await wipeService.wipeFirestoreData();

    final superDoc = await firestore.collection('users').doc('super-uid').get();
    expect(superDoc.data()!['businessAccess'], {'business-1': 'businessAdmin'});

    final staffDoc = await firestore.collection('users').doc('staff-uid').get();
    expect(staffDoc.data()!['businessAccess'], <String, Object?>{});
  });
}
