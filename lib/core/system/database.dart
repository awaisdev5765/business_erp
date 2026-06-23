import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/fishery/fish_category.dart';
import '../../features/fishery/fish_sale.dart';
import '../../features/spare_parts/inventory/category.dart';
import '../../features/spare_parts/inventory/product.dart';
import '../../features/spare_parts/purchases/purchase.dart';
import '../../features/spare_parts/sales/sale.dart';
import '../../features/transport/contract.dart';
import '../../features/transport/trip_income.dart';
import '../accounting/account.dart';
import '../accounting/bank_account.dart';
import '../accounting/fiscal_period.dart';
import '../accounting/journal_entry.dart';
import '../accounting/tax_rate.dart';
import '../activity/trip.dart';
import '../activity/trip_expense.dart';
import '../asset/operating_asset.dart';
import '../party/party.dart';
import '../sync/conflict_record.dart';
import '../sync/sync_queue_item.dart';
import '../tenant/business.dart';
import '../transaction/payment.dart';
import 'audit_log.dart';
import 'number_sequence.dart';

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
        onCreate: (db, version) => createSchema(db),
      ),
    );
    return _instance!;
  }
}

/// Creates every table/index in the schema. Shared by [AppDatabase.open]
/// and by tests, so the two never drift out of sync as new modules add
/// tables.
Future<void> createSchema(DatabaseExecutor db) async {
  await db.execute(Business.createTableSql);
  await db.execute(Account.createTableSql);
  await db.execute(Account.createIndexSql);
  await db.execute(JournalEntry.createTableSql);
  await db.execute(JournalEntry.createIndexSql);
  await db.execute(JournalEntry.createStatusIndexSql);
  await db.execute(JournalLine.createTableSql);
  await db.execute(JournalLine.createIndexSql);
  await db.execute(JournalLine.createEntryIndexSql);
  await db.execute(JournalLine.createPartyIndexSql);
  await db.execute(JournalLine.createDimensionIndexSql);
  await db.execute(Party.createTableSql);
  await db.execute(Party.createIndexSql);
  await db.execute(NumberSequence.createTableSql);
  await db.execute(Category.createTableSql);
  await db.execute(Brand.createTableSql);
  await db.execute(Product.createTableSql);
  await db.execute(Product.createIndexSql);
  await db.execute(StockMovement.createTableSql);
  await db.execute(StockMovement.createIndexSql);
  await db.execute(Purchase.createTableSql);
  await db.execute(Purchase.createIndexSql);
  await db.execute(PurchaseLine.createTableSql);
  await db.execute(PurchaseLine.createIndexSql);
  await db.execute(Sale.createTableSql);
  await db.execute(Sale.createIndexSql);
  await db.execute(SaleLine.createTableSql);
  await db.execute(SaleLine.createIndexSql);
  await db.execute(Payment.createTableSql);
  await db.execute(Payment.createIndexSql);
  await db.execute(FiscalPeriod.createTableSql);
  await db.execute(FiscalPeriod.createIndexSql);
  await db.execute(TaxRate.createTableSql);
  await db.execute(AuditLog.createTableSql);
  await db.execute(AuditLog.createIndexSql);
  await db.execute(BankAccount.createTableSql);
  await db.execute(BankStatementLine.createTableSql);
  await db.execute(BankStatementLine.createIndexSql);
  await db.execute(OperatingAsset.createTableSql);
  await db.execute(OperatingAsset.createIndexSql);
  await db.execute(Trip.createTableSql);
  await db.execute(Trip.createIndexSql);
  await db.execute(TripExpense.createTableSql);
  await db.execute(TripExpense.createIndexSql);
  await db.execute(FishCategory.createTableSql);
  await db.execute(CatchEntry.createTableSql);
  await db.execute(CatchEntry.createIndexSql);
  await db.execute(FishSale.createTableSql);
  await db.execute(FishSale.createIndexSql);
  await db.execute(Contract.createTableSql);
  await db.execute(Contract.createIndexSql);
  await db.execute(TripIncome.createTableSql);
  await db.execute(TripIncome.createIndexSql);
  await db.execute(SyncQueueItem.createTableSql);
  await db.execute(SyncQueueItem.createIndexSql);
  await db.execute(ConflictRecord.createTableSql);
  await db.execute(ConflictRecord.createIndexSql);
}
