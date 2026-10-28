import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// Super-Admin-only "wipe everything" — every business's local ledger
/// data and the matching Firestore mirror, leaving only the Super
/// Admin's own account. Staff Firebase Auth *logins* can't actually be
/// deleted from client code (that needs the Admin SDK, unavailable on
/// the free Spark plan without Cloud Functions) — this strips every
/// staff profile's businessAccess instead (same effect StaffManagement
/// Screen's "Deactivate" already has: locked out everywhere, even
/// though the email/password technically still exists until removed by
/// hand in the Firebase Console).
///
/// Irreversible. The UI calling this (see app.dart's danger-zone
/// button) is responsible for confirming intent before ever calling
/// these methods — this class does no confirmation of its own.
class DataWipeService {
  DataWipeService(this.db, this.firestore);

  final Database db;
  final FirebaseFirestore firestore;

  /// Every subcollection [FirestoreSyncService] has ever written under
  /// `/businesses/{id}/`. Must stay complete — an incomplete list is
  /// why wipe looked like a no-op: business docs got deleted, but
  /// leftover collections + a re-created business profile (or a
  /// partially-failed wipe) could bring data back on the next restore.
  static const businessSubcollections = [
    'parties',
    'products',
    'journalEntries',
    'numberSequences',
    'categories',
    'brands',
    'operatingAssets',
    'trips',
    'tripExpenses',
    'fishCategories',
    'catchEntries',
    'fishSales',
    'contracts',
    'tripIncomes',
    'weightEntries',
    'monthlySettlements',
    'vehicleKhataLines',
    'paymentRecords',
    'salaryRecords',
    'salaryPayments',
    'fixedAssets',
    'depreciationEntries',
    'bankAccounts',
    'bankStatementLines',
    'fiscalPeriods',
    'taxRates',
    'stockMovements',
    'sales',
    'purchases',
    'refunds',
    'approvalThresholds',
    'auditLogs',
  ];

  /// Drops every local table and recreates an empty schema. On web the
  /// IndexedDB-backed SQLite file is deleted outright — DROP TABLE alone
  /// has left stale data in sql.js/IndexedDB in practice.
  Future<void> wipeLocalDatabase() async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    await db.transaction((txn) async {
      for (final row in tables) {
        await txn.execute('DROP TABLE IF EXISTS "${row['name']}"');
      }
    });

    if (kIsWeb) {
      final path = db.path;
      await db.close();
      await databaseFactory.deleteDatabase(path);
      await AppDatabase.resetAndOpen();
    } else {
      await createSchema(db);
    }
  }

  Future<void> wipeFirestoreData() async {
    final businesses = await firestore.collection('businesses').get();
    for (final business in businesses.docs) {
      for (final sub in businessSubcollections) {
        await _deleteCollection(business.reference.collection(sub));
      }
      await business.reference.delete();
    }

    // Strip every staff profile's access rather than deleting the
    // doc outright — same as StaffManagementScreen's "Deactivate".
    // The Super Admin's own profile (isSuperAdmin == true) is left
    // completely untouched.
    //
    // A full set() of the merged data, not update() — fake_cloud_
    // firestore (and, going by some real Firestore SDK reports,
    // occasionally the genuine client too) doesn't reliably apply an
    // update() whose only change is replacing a field with an *empty*
    // map; rewriting the whole document sidesteps that entirely.
    final users = await firestore.collection('users').get();
    for (final userDoc in users.docs) {
      final data = userDoc.data();
      if (data['isSuperAdmin'] == true) continue;
      await userDoc.reference.set({...data, 'businessAccess': <String, Object?>{}});
    }
  }

  /// Local first so the device is empty even if Firestore hits a
  /// permission/network error mid-way — then cloud. Callers should still
  /// surface cloud failures.
  Future<void> wipeEverything() async {
    await wipeLocalDatabase();
    await wipeFirestoreData();
  }

  /// Firestore has no recursive-delete on the client SDK (that's an
  /// Admin SDK / firebase-tools-only feature) — fetch then batch-delete
  /// every doc, chunked well under the 500-write batch limit.
  Future<void> _deleteCollection(CollectionReference<Map<String, Object?>> collection) async {
    // Paginate — a single .get() can miss docs on large collections and
    // leave orphans that restoreFromCloud later brings back.
    while (true) {
      final docs = await collection.limit(400).get();
      if (docs.docs.isEmpty) return;
      final batch = firestore.batch();
      for (final doc in docs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (docs.docs.length < 400) return;
    }
  }
}
