import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'operating_asset.dart';

const _uuid = Uuid();

class OperatingAssetRepository {
  OperatingAssetRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<OperatingAsset> create({
    required String businessId,
    required OperatingAssetType type,
    required String name,
    String? registrationNumber,
  }) async {
    final asset = OperatingAsset(
      uuid: _uuid.v4(),
      businessId: businessId,
      type: type,
      name: name,
      registrationNumber: registrationNumber,
    );
    await db.insert(OperatingAsset.tableName, asset.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'OperatingAsset',
        entityId: asset.uuid,
        operation: SyncOperation.create,
      );
    }
    return asset;
  }

  Future<List<OperatingAsset>> list({required String businessId, required OperatingAssetType type}) async {
    final rows = await db.query(
      OperatingAsset.tableName,
      where: 'business_id = ? AND type = ? AND is_active = 1',
      whereArgs: [businessId, type.name],
      orderBy: 'name ASC',
    );
    return rows.map(OperatingAsset.fromMap).toList();
  }

  Future<OperatingAsset?> findByUuid(String uuid) async {
    final rows = await db.query(OperatingAsset.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : OperatingAsset.fromMap(rows.first);
  }
}
