import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../../features/fishery/fish_category.dart';
import '../../features/fishery/fish_sale.dart';
import '../../features/spare_parts/inventory/category.dart';
import '../../features/spare_parts/inventory/product.dart';
import '../../features/spare_parts/purchases/purchase.dart';
import '../../features/spare_parts/sales/refund.dart';
import '../../features/spare_parts/sales/sale.dart';
import '../../features/transport/contract.dart';
import '../../features/transport/monthly_settlement.dart';
import '../../features/transport/trip_income.dart';
import '../../features/transport/vehicle_khata_line.dart';
import '../../features/transport/weight_entry.dart';
import '../accounting/account.dart';
import '../accounting/approval_threshold.dart';
import '../accounting/balance_rollup.dart';
import '../accounting/bank_account.dart';
import '../accounting/expense.dart';
import '../accounting/fiscal_period.dart';
import '../accounting/fixed_asset.dart';
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
import '../transaction/salary_record.dart';
import 'audit_log.dart';
import 'number_sequence.dart';

/// Single SQLite instance for the whole app. Firestore (when wired in a
/// later phase) is sync/backup only — this is the runtime database. See
/// PHASES.md Section 14.
///
/// sqflite's platform channel only covers Android/iOS. On Windows/macOS/
/// Linux (and in `flutter test`) we swap in sqflite_common_ffi's
/// databaseFactory (native FFI). On web, `dart:io`'s `Platform` itself
/// throws `UnsupportedError` the moment it's touched — `kIsWeb` must be
/// checked *before* any `Platform.*` access, not just before choosing a
/// factory — so web gets its own branch using `sqflite_common_ffi_web`
/// (sql.js/wasm + IndexedDB persistence) with no `path_provider` call,
/// since that plugin has no web implementation either.
class AppDatabase {
  static Database? _instance;

  static Future<Database> open() async {
    if (_instance != null) return _instance!;

    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      _instance = await databaseFactory.openDatabase(
        'business_erp.db',
        options: OpenDatabaseOptions(
          version: _schemaVersion,
          onCreate: (db, version) => createSchema(db),
          onUpgrade: migrateSchema,
        ),
      );
      return _instance!;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'business_erp.db');

    _instance = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (db, version) => createSchema(db),
        onUpgrade: migrateSchema,
      ),
    );
    return _instance!;
  }

  /// After a full wipe (especially on web IndexedDB) — drop the cached
  /// handle and open a fresh empty database.
  static Future<Database> resetAndOpen() async {
    if (_instance != null) {
      try {
        await _instance!.close();
      } catch (_) {}
      _instance = null;
    }
    return open();
  }
}

/// Bump whenever createSchema()'s table definitions change shape (new
/// columns, new tables) — see [migrateSchema] for what each version
/// past 1 actually does to an already-existing database. A brand new
/// database always gets the latest shape directly via [createSchema];
/// migrations only run for a database that already existed at a lower
/// version (i.e. real installs with real data, not fresh ones).
const _schemaVersion = 7;

/// v1 -> v2: added Business.address/phone and Payment.method/note.
/// v2 -> v3: added Sale.discount_minor_units and the new Expense table
/// — see PHASES.md's post-launch "discount + general expense flow"
/// work. SQLite's ALTER TABLE only supports adding one column at a
/// time with a constant DEFAULT (no backfill logic needed here — every
/// existing row just gets the column's default).
/// v3 -> v4: added the Refund/RefundLine tables for qty-wise partial
/// refunds (see refund.dart) — purely additive, no existing column
/// changes, so nothing to backfill.
/// v4 -> v5: number_sequences gained a `year` column and moved to
/// PRIMARY KEY (business_id, doc_type, year), so document numbers reset
/// every January (NumberSequenceService). SQLite's ALTER TABLE can't
/// change a primary key, so the table is rebuilt: existing counters are
/// carried over into the *current* year's row (rather than reset to 0),
/// so a business mid-way through its 2026 numbers doesn't suddenly
/// reissue numbers it already printed on paper receipts.
/// v5 -> v6: transport weight register + month hisaab (WeightEntry,
/// MonthlySettlement), company rate-per-ton, and trip_expenses rebuilt
/// so vehicle khata expenses can exist without a trip (nullable
/// trip_uuid + asset_uuid).
/// v6 -> v7: Company Bills weight is kg (not tons); Gari Khata running
/// ledger table (Date / Tafseel / Kharcha / Jama).
Future<void> migrateSchema(DatabaseExecutor db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE ${Business.tableName} ADD COLUMN address TEXT');
    await db.execute('ALTER TABLE ${Business.tableName} ADD COLUMN phone TEXT');
    await db.execute("ALTER TABLE ${Payment.tableName} ADD COLUMN method TEXT NOT NULL DEFAULT 'cash'");
    await db.execute('ALTER TABLE ${Payment.tableName} ADD COLUMN note TEXT');
  }
  if (oldVersion < 3) {
    await db.execute('ALTER TABLE ${Sale.tableName} ADD COLUMN discount_minor_units INTEGER NOT NULL DEFAULT 0');
    await db.execute(Expense.createTableSql);
    await db.execute(Expense.createIndexSql);
  }
  if (oldVersion < 4) {
    await db.execute(Refund.createTableSql);
    await db.execute(Refund.createIndexSql);
    await db.execute(Refund.createBusinessDateIndexSql);
    await db.execute(RefundLine.createTableSql);
    await db.execute(RefundLine.createIndexSql);
    await db.execute(RefundLine.createSaleLineIndexSql);
  }
  if (oldVersion < 5) {
    final currentYear = DateTime.now().year;
    await db.execute('ALTER TABLE ${NumberSequence.tableName} RENAME TO number_sequences_old');
    await db.execute(NumberSequence.createTableSql);
    await db.execute('''
      INSERT INTO ${NumberSequence.tableName} (business_id, doc_type, year, last_number)
      SELECT business_id, doc_type, $currentYear, last_number FROM number_sequences_old
    ''');
    await db.execute('DROP TABLE number_sequences_old');
  }
  if (oldVersion < 6) {
    await db.execute('ALTER TABLE ${Contract.tableName} ADD COLUMN rate_per_ton_minor_units INTEGER');
    // Frozen v6 shape (weight in tons). v7 converts to kg.
    await db.execute('''
      CREATE TABLE weight_entries (
        uuid TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        vehicle_uuid TEXT NOT NULL,
        company_uuid TEXT NOT NULL,
        date TEXT NOT NULL,
        weight_tons REAL NOT NULL,
        notes TEXT,
        settlement_uuid TEXT,
        amount_minor_units INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_weight_entries_business_date ON weight_entries (business_id, date)');
    await db.execute('CREATE INDEX idx_weight_entries_vehicle ON weight_entries (vehicle_uuid, date)');
    await db.execute('CREATE INDEX idx_weight_entries_company ON weight_entries (company_uuid, date)');
    await db.execute('''
      CREATE TABLE monthly_settlements (
        uuid TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        company_uuid TEXT NOT NULL,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        rate_per_ton_minor_units INTEGER NOT NULL,
        total_weight_tons REAL NOT NULL,
        amount_minor_units INTEGER NOT NULL,
        date TEXT NOT NULL,
        UNIQUE (business_id, company_uuid, year, month)
      )
    ''');
    await db.execute('CREATE INDEX idx_monthly_settlements_business ON monthly_settlements (business_id, year, month)');

    await db.execute('ALTER TABLE ${TripExpense.tableName} RENAME TO trip_expenses_old');
    await db.execute(TripExpense.createTableSql);
    await db.execute('''
      INSERT INTO ${TripExpense.tableName}
        (uuid, trip_uuid, asset_uuid, business_id, category, amount_minor_units, description, date)
      SELECT te.uuid, te.trip_uuid, t.asset_uuid, te.business_id, te.category,
             te.amount_minor_units, te.description, te.date
      FROM trip_expenses_old te
      LEFT JOIN ${Trip.tableName} t ON t.uuid = te.trip_uuid
    ''');
    await db.execute('DROP TABLE trip_expenses_old');
    await db.execute(TripExpense.createIndexSql);
    await db.execute(TripExpense.createAssetIndexSql);
  }
  if (oldVersion < 7) {
    await db.execute('ALTER TABLE ${WeightEntry.tableName} ADD COLUMN weight_kg REAL');
    await db.execute(
      'UPDATE ${WeightEntry.tableName} SET weight_kg = weight_tons * 1000 WHERE weight_kg IS NULL',
    );
    await db.execute('ALTER TABLE ${MonthlySettlement.tableName} ADD COLUMN total_weight_kg REAL');
    await db.execute(
      'UPDATE ${MonthlySettlement.tableName} SET total_weight_kg = total_weight_tons * 1000 WHERE total_weight_kg IS NULL',
    );
    await db.execute(VehicleKhataLine.createTableSql);
    await db.execute(VehicleKhataLine.createIndexSql);
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
  await db.execute(Refund.createTableSql);
  await db.execute(Refund.createIndexSql);
  await db.execute(Refund.createBusinessDateIndexSql);
  await db.execute(RefundLine.createTableSql);
  await db.execute(RefundLine.createIndexSql);
  await db.execute(RefundLine.createSaleLineIndexSql);
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
  await db.execute(TripExpense.createAssetIndexSql);
  await db.execute(FishCategory.createTableSql);
  await db.execute(CatchEntry.createTableSql);
  await db.execute(CatchEntry.createIndexSql);
  await db.execute(FishSale.createTableSql);
  await db.execute(FishSale.createIndexSql);
  await db.execute(Contract.createTableSql);
  await db.execute(Contract.createIndexSql);
  await db.execute(TripIncome.createTableSql);
  await db.execute(TripIncome.createIndexSql);
  await db.execute(WeightEntry.createTableSql);
  await db.execute(WeightEntry.createIndexSql);
  await db.execute(WeightEntry.createVehicleIndexSql);
  await db.execute(WeightEntry.createCompanyIndexSql);
  await db.execute(MonthlySettlement.createTableSql);
  await db.execute(MonthlySettlement.createIndexSql);
  await db.execute(VehicleKhataLine.createTableSql);
  await db.execute(VehicleKhataLine.createIndexSql);
  await db.execute(SyncQueueItem.createTableSql);
  await db.execute(SyncQueueItem.createIndexSql);
  await db.execute(ConflictRecord.createTableSql);
  await db.execute(ConflictRecord.createIndexSql);
  await db.execute(FixedAsset.createTableSql);
  await db.execute(FixedAsset.createIndexSql);
  await db.execute(DepreciationEntry.createTableSql);
  await db.execute(DepreciationEntry.createIndexSql);
  await db.execute(ApprovalThreshold.createTableSql);
  await db.execute(SalaryRecord.createTableSql);
  await db.execute(SalaryRecord.createIndexSql);
  await db.execute(SalaryPayment.createTableSql);
  await db.execute(SalaryPayment.createIndexSql);
  await db.execute(AccountBalanceRollup.createTableSql);
  await db.execute(PartyBalanceRollup.createTableSql);
  await db.execute(Expense.createTableSql);
  await db.execute(Expense.createIndexSql);
}
