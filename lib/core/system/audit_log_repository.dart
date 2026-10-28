import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'audit_log.dart';

const _uuid = Uuid();

class AuditLogRepository {
  AuditLogRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<void> log({
    required String businessId,
    required String action,
    required String entityType,
    required String entityId,
    required String performedBy,
    String? details,
  }) async {
    final entry = AuditLog(
      id: _uuid.v4(),
      businessId: businessId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      performedBy: performedBy,
      performedAt: DateTime.now(),
      details: details,
    );
    await db.insert(AuditLog.tableName, entry.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'AuditLog',
        entityId: entry.id,
        operation: SyncOperation.create,
      );
    }
  }

  Future<List<AuditLog>> list({required String businessId}) async {
    final rows = await db.query(
      AuditLog.tableName,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'performed_at DESC',
    );
    return rows.map(AuditLog.fromMap).toList();
  }
}
