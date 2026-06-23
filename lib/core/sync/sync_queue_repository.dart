import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'sync_queue_item.dart';

const _uuid = Uuid();

class SyncQueueRepository {
  SyncQueueRepository(this.db);

  final Database db;

  /// Enqueues one entity for upload. Call this from the same transaction
  /// as the entity's own insert/update (pass [txn]) so the queue entry
  /// can never be missing for a record that was actually written — see
  /// LedgerRepository.postWithin() for the first wired example.
  Future<void> enqueue(
    DatabaseExecutor txn, {
    required String businessId,
    required String entityType,
    required String entityId,
    required SyncOperation operation,
  }) async {
    final now = DateTime.now();
    final item = SyncQueueItem(
      id: _uuid.v4(),
      businessId: businessId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      createdAt: now,
      updatedAt: now,
    );
    await txn.insert(SyncQueueItem.tableName, item.toMap());
  }

  Future<List<SyncQueueItem>> pending({required String businessId}) async {
    final rows = await db.query(
      SyncQueueItem.tableName,
      where: 'business_id = ? AND status IN (?, ?)',
      whereArgs: [businessId, SyncQueueStatus.pending.name, SyncQueueStatus.failed.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  Future<List<SyncQueueItem>> all({required String businessId}) async {
    final rows = await db.query(
      SyncQueueItem.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  Future<int> pendingCount({required String businessId}) async {
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS count FROM ${SyncQueueItem.tableName}
      WHERE business_id = ? AND status IN (?, ?)
    ''', [businessId, SyncQueueStatus.pending.name, SyncQueueStatus.failed.name]);
    return result.first['count'] as int;
  }

  Future<void> markSynced(String id) async {
    await db.update(
      SyncQueueItem.tableName,
      {'status': SyncQueueStatus.synced.name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records a failed sync attempt with backoff bookkeeping (attempts++,
  /// the error message) but leaves status as `failed` rather than
  /// `conflict` — see [markConflict] for the distinction.
  Future<void> markFailed(String id, String error) async {
    final rows = await db.query(SyncQueueItem.tableName, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final current = SyncQueueItem.fromMap(rows.first);

    await db.update(
      SyncQueueItem.tableName,
      {
        'status': SyncQueueStatus.failed.name,
        'attempts': current.attempts + 1,
        'last_error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// A conflict is different from a transient failure: the upload reached
  /// the server but the server detected a competing edit. This needs a
  /// human decision (see ConflictResolutionService), not just a retry.
  Future<void> markConflict(String id, String details) async {
    await db.update(
      SyncQueueItem.tableName,
      {
        'status': SyncQueueStatus.conflict.name,
        'last_error': details,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
