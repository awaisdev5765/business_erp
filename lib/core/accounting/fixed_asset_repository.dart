import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_queue_item.dart';
import '../sync/sync_queue_repository.dart';
import 'fixed_asset.dart';

const _uuid = Uuid();

class FixedAssetRepository {
  FixedAssetRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<FixedAsset> create({
    required String businessId,
    required String name,
    String? operatingAssetUuid,
    required DateTime acquisitionDate,
    required int acquisitionCostMinorUnits,
    required int usefulLifeMonths,
    int salvageValueMinorUnits = 0,
  }) async {
    final asset = FixedAsset(
      uuid: _uuid.v4(),
      businessId: businessId,
      name: name,
      operatingAssetUuid: operatingAssetUuid,
      acquisitionDate: acquisitionDate,
      acquisitionCostMinorUnits: acquisitionCostMinorUnits,
      usefulLifeMonths: usefulLifeMonths,
      salvageValueMinorUnits: salvageValueMinorUnits,
    );
    await db.insert(FixedAsset.tableName, asset.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'FixedAsset',
        entityId: asset.uuid,
        operation: SyncOperation.create,
      );
    }
    return asset;
  }

  Future<List<FixedAsset>> list({required String businessId}) async {
    final rows = await db.query(
      FixedAsset.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'acquisition_date DESC',
    );
    return rows.map(FixedAsset.fromMap).toList();
  }

  Future<FixedAsset?> findByUuid(String uuid) async {
    final rows = await db.query(FixedAsset.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : FixedAsset.fromMap(rows.first);
  }

  Future<List<DepreciationEntry>> depreciationHistory(String fixedAssetUuid) async {
    final rows = await db.query(
      DepreciationEntry.tableName,
      where: 'fixed_asset_uuid = ?',
      whereArgs: [fixedAssetUuid],
      orderBy: 'period ASC',
    );
    return rows.map(DepreciationEntry.fromMap).toList();
  }

  Future<int> accumulatedDepreciation(String fixedAssetUuid) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_minor_units), 0) AS total FROM ${DepreciationEntry.tableName} WHERE fixed_asset_uuid = ?',
      [fixedAssetUuid],
    );
    return result.first['total'] as int;
  }

  /// Acquisition cost minus accumulated depreciation — never below the
  /// salvage value, since depreciation should never reduce book value
  /// past that floor.
  Future<int> bookValue(FixedAsset asset) async {
    final accumulated = await accumulatedDepreciation(asset.uuid);
    final value = asset.acquisitionCostMinorUnits - accumulated;
    return value < asset.salvageValueMinorUnits ? asset.salvageValueMinorUnits : value;
  }
}
