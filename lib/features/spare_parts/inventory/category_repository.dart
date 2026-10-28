import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/sync_queue_item.dart';
import '../../../core/sync/sync_queue_repository.dart';
import 'category.dart';

const _uuid = Uuid();

/// Categories/Brands existed in the schema since Phase 1 (Product.
/// categoryUuid/brandUuid) but never had a repository or any UI to
/// create one — ProductListScreen's "New Product" dialog only ever set
/// those fields to null. This is that missing piece.
class CategoryRepository {
  CategoryRepository(this.db, [this.syncQueue]);

  final Database db;
  final SyncQueueRepository? syncQueue;

  Future<Category> create({required String businessId, required String name}) async {
    final category = Category(uuid: _uuid.v4(), businessId: businessId, name: name);
    await db.insert(Category.tableName, category.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'Category',
        entityId: category.uuid,
        operation: SyncOperation.create,
      );
    }
    return category;
  }

  /// One-at-a-time create() was fine for the occasional new category,
  /// but onboarding a shop with an existing catalog (dozens of
  /// categories already in their head, or copied from a spreadsheet)
  /// meant retyping the same dialog over and over. Skips names that
  /// already exist for this business (case-insensitive) rather than
  /// creating duplicates.
  Future<List<Category>> createMany({required String businessId, required List<String> names}) async {
    final existing = await list(businessId: businessId);
    final existingLower = existing.map((c) => c.name.toLowerCase()).toSet();

    final created = <Category>[];
    for (final rawName in names) {
      final name = rawName.trim();
      if (name.isEmpty || existingLower.contains(name.toLowerCase())) continue;
      created.add(await create(businessId: businessId, name: name));
      existingLower.add(name.toLowerCase());
    }
    return created;
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
