import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Drops every local table (enumerated from sqlite_master, so this
  /// never drifts out of sync with whatever tables createSchema()
  /// currently defines) and recreates the empty schema.
  Future<void> wipeLocalDatabase() async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    await db.transaction((txn) async {
      for (final row in tables) {
        await txn.execute('DROP TABLE IF EXISTS "${row['name']}"');
      }
    });
    await createSchema(db);
  }

  /// Subcollections written under /businesses/{id}/ — see
  /// FirestoreSyncService. Kept as an explicit list (rather than
  /// listing subcollections at runtime, which the client SDK can't do)
  /// since these are the only ones this app has ever written.
  static const _businessSubcollections = ['parties', 'products', 'journalEntries', 'numberSequences'];

  Future<void> wipeFirestoreData() async {
    final businesses = await firestore.collection('businesses').get();
    for (final business in businesses.docs) {
      for (final sub in _businessSubcollections) {
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

  Future<void> wipeEverything() async {
    await wipeFirestoreData();
    await wipeLocalDatabase();
  }

  /// Firestore has no recursive-delete on the client SDK (that's an
  /// Admin SDK / firebase-tools-only feature) — fetch then batch-delete
  /// every doc, chunked well under the 500-write batch limit.
  Future<void> _deleteCollection(CollectionReference<Map<String, Object?>> collection) async {
    final docs = await collection.get();
    const chunkSize = 400;
    for (var i = 0; i < docs.docs.length; i += chunkSize) {
      final batch = firestore.batch();
      for (final doc in docs.docs.skip(i).take(chunkSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
