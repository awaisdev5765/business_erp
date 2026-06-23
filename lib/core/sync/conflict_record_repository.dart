import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'conflict_record.dart';

const _uuid = Uuid();

class ConflictRecordRepository {
  ConflictRecordRepository(this.db);

  final Database db;

  Future<ConflictRecord> record({
    required String businessId,
    required String entityType,
    required String entityId,
    required List<String> conflictingFields,
  }) async {
    final record = ConflictRecord(
      id: _uuid.v4(),
      businessId: businessId,
      entityType: entityType,
      entityId: entityId,
      conflictingFields: conflictingFields,
      detectedAt: DateTime.now(),
    );
    await db.insert(ConflictRecord.tableName, record.toMap());
    return record;
  }

  Future<List<ConflictRecord>> unresolved({required String businessId}) async {
    final rows = await db.query(
      ConflictRecord.tableName,
      where: 'business_id = ? AND status = ?',
      whereArgs: [businessId, ConflictRecordStatus.unresolved.name],
      orderBy: 'detected_at ASC',
    );
    return rows.map(ConflictRecord.fromMap).toList();
  }

  Future<void> resolve(String id, ConflictRecordStatus resolution) async {
    if (resolution == ConflictRecordStatus.unresolved) {
      throw ArgumentError('resolve() requires a resolved status, not unresolved');
    }
    await db.update(
      ConflictRecord.tableName,
      {'status': resolution.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
