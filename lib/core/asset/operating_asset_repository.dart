import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'operating_asset.dart';

const _uuid = Uuid();

class OperatingAssetRepository {
  OperatingAssetRepository(this.db);

  final Database db;

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
