import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'category.dart';

const _uuid = Uuid();

/// Categories/Brands existed in the schema since Phase 1 (Product.
/// categoryUuid/brandUuid) but never had a repository or any UI to
/// create one — ProductListScreen's "New Product" dialog only ever set
/// those fields to null. This is that missing piece.
class CategoryRepository {
  CategoryRepository(this.db);

  final Database db;

  Future<Category> create({required String businessId, required String name}) async {
    final category = Category(uuid: _uuid.v4(), businessId: businessId, name: name);
    await db.insert(Category.tableName, category.toMap());
    return category;
  }

  Future<List<Category>> list({required String businessId}) async {
    final rows = await db.query(
      Category.tableName,
      where: 'business_id = ? AND is_active = 1',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(Category.fromMap).toList();
  }
}
