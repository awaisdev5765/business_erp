import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync/sync_queue_item.dart';
import '../../core/sync/sync_queue_repository.dart';
import 'fish_category.dart';

const _uuid = Uuid();

class FishCategoryRepository {
  FishCategoryRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<FishCategory> create({required String businessId, required String name}) async {
    final category = FishCategory(uuid: _uuid.v4(), businessId: businessId, name: name);
    await db.insert(FishCategory.tableName, category.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'FishCategory',
        entityId: category.uuid,
        operation: SyncOperation.create,
      );
    }
    return category;
  }

  Future<List<FishCategory>> list({required String businessId}) async {
    final rows = await db.query(
      FishCategory.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(FishCategory.fromMap).toList();
  }

  Future<FishCategory?> findByUuid(String uuid) async {
    final rows = await db.query(FishCategory.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : FishCategory.fromMap(rows.first);
  }
}

class CatchRepository {
  CatchRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<CatchEntry> record({
    required String tripUuid,
    required String businessId,
    required String fishCategoryUuid,
    required double weightKg,
    int? estimatedValueMinorUnits,
  }) async {
    final entry = CatchEntry(
      uuid: _uuid.v4(),
      tripUuid: tripUuid,
      businessId: businessId,
      fishCategoryUuid: fishCategoryUuid,
      weightKg: weightKg,
      estimatedValueMinorUnits: estimatedValueMinorUnits,
    );
    await db.insert(CatchEntry.tableName, entry.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'CatchEntry',
        entityId: entry.uuid,
        operation: SyncOperation.create,
      );
    }
    return entry;
  }

  Future<List<CatchEntry>> listByTrip(String tripUuid) async {
    final rows = await db.query(CatchEntry.tableName, where: 'trip_uuid = ?', whereArgs: [tripUuid]);
    return rows.map(CatchEntry.fromMap).toList();
  }
}
