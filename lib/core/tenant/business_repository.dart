import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/chart_of_accounts_seed.dart';
import 'business.dart';

const _uuid = Uuid();

/// Until Phase 6, the app only ever had one auto-seeded business and no
/// way to add another — see PHASES.md "Known gap" notes carried since
/// Phase 1. This is the Business Switcher's data layer.
class BusinessRepository {
  BusinessRepository(this.db);

  final Database db;

  Future<Business> create({required String name, required BusinessType type}) async {
    final now = DateTime.now();
    final business = Business(
      uuid: _uuid.v4(),
      name: name,
      type: type,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(Business.tableName, business.toMap());
    await seedChartOfAccounts(db, business.uuid);
    return business;
  }

  Future<List<Business>> list() async {
    final rows = await db.query(Business.tableName, where: 'is_active = 1', orderBy: 'name ASC');
    return rows.map(Business.fromMap).toList();
  }

  Future<Business?> findByUuid(String uuid) async {
    final rows = await db.query(Business.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : Business.fromMap(rows.first);
  }

  /// Soft-deletes a business — sets `is_active = 0` so `list()` stops
  /// returning it (and therefore the Business Switcher/nav/Cross-
  /// Business Dashboard), without touching its ledger data. Never a
  /// hard delete, same append-only philosophy as Void vs. Reversal for
  /// journal entries — an archived business's history stays queryable
  /// by uuid if ever needed, it just stops showing up day to day.
  Future<void> archive(String uuid) async {
    await db.update(
      Business.tableName,
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
}
