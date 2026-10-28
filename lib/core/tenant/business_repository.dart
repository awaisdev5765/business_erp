import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../accounting/chart_of_accounts_seed.dart';
import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'business.dart';

const _uuid = Uuid();

/// Until Phase 6, the app only ever had one auto-seeded business and no
/// way to add another — see PHASES.md "Known gap" notes carried since
/// Phase 1. This is the Business Switcher's data layer.
///
/// [syncQueue] is optional, same opt-in pattern as Party/Product —
/// without it, a business lives only in this device's local SQLite
/// (which on web is the experimental IndexedDB-backed sqflite_common_
/// ffi_web — known to be lossy across a closed/reopened browser tab, see
/// FirestoreSyncService's restoreFromCloud()). Wiring it in lets the
/// business itself be re-downloaded from Firestore if local storage is
/// ever wiped, instead of being unrecoverable.
class BusinessRepository {
  BusinessRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<Business> create({
    required String name,
    required BusinessType type,
    String? baseCurrency,
    String? address,
    String? phone,
  }) async {
    final now = DateTime.now();
    final business = Business(
      uuid: _uuid.v4(),
      name: name,
      type: type,
      baseCurrency: baseCurrency,
      address: address,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert(Business.tableName, business.toMap());
      if (syncQueue != null) {
        await syncQueue!.enqueue(
          txn,
          businessId: business.uuid,
          entityType: 'Business',
          entityId: business.uuid,
          operation: SyncOperation.create,
        );
      }
    });
    await seedChartOfAccounts(db, business.uuid);
    return business;
  }

  /// Edits an existing business's profile — name, currency, address,
  /// phone. There was no way to change any of this once created; only
  /// `create()` ever set these fields. Super-Admin-only at the UI layer
  /// (BusinessSwitcherScreen).
  Future<void> update(Business business) async {
    await db.update(
      Business.tableName,
      business.toMap(),
      where: 'uuid = ?',
      whereArgs: [business.uuid],
    );
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: business.uuid,
        entityType: 'Business',
        entityId: business.uuid,
        operation: SyncOperation.update,
      );
    }
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
