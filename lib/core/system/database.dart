import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../accounting/account.dart';
import '../accounting/journal_entry.dart';
import '../tenant/business.dart';

/// Single SQLite instance for the whole app. Firestore (when wired in a
/// later phase) is sync/backup only — this is the runtime database. See
/// PHASES.md Section 14.
///
/// sqflite's platform channel only covers Android/iOS. On Windows/macOS/
/// Linux (and in `flutter test`) we swap in sqflite_common_ffi's
/// databaseFactory, which talks to SQLite directly via FFI.
class AppDatabase {
  static Database? _instance;

  static Future<Database> open() async {
    if (_instance != null) return _instance!;

    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'business_erp.db');

    _instance = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(Business.createTableSql);
          await db.execute(Account.createTableSql);
          await db.execute(Account.createIndexSql);
          await db.execute(JournalEntry.createTableSql);
          await db.execute(JournalEntry.createIndexSql);
          await db.execute(JournalEntry.createStatusIndexSql);
          await db.execute(JournalLine.createTableSql);
          await db.execute(JournalLine.createIndexSql);
          await db.execute(JournalLine.createEntryIndexSql);
        },
      ),
    );
    return _instance!;
  }
}
