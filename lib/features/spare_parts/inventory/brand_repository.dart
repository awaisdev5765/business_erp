import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'category.dart';

const _uuid = Uuid();

/// Mirrors CategoryRepository exactly — Brand existed in the schema
/// since Phase 1 (Product.brandUuid) alongside Category, but only
/// Category ever got a repository or UI. Same gap, same fix.
class BrandRepository {
  BrandRepository(this.db);

  final Database db;

  Future<Brand> create({required String businessId, required String name}) async {
    final brand = Brand(uuid: _uuid.v4(), businessId: businessId, name: name);
    await db.insert(Brand.tableName, brand.toMap());
    return brand;
  }

  Future<List<Brand>> list({required String businessId}) async {
    final rows = await db.query(
      Brand.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(Brand.fromMap).toList();
  }
}
