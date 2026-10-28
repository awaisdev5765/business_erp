import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/sync_queue_item.dart';
import '../../../core/sync/sync_queue_repository.dart';
import '../../../core/system/audit_log_repository.dart';
import 'product.dart';

const _uuid = Uuid();

class ProductRepository {
  /// [syncQueue]/[auditLog] are optional, same opt-in pattern as
  /// elsewhere.
  ProductRepository(this.db, [this.syncQueue, this.auditLog]);

  final Database db;
  final SyncQueueRepository? syncQueue;
  final AuditLogRepository? auditLog;

  Future<Product> create({
    required String businessId,
    required String sku,
    required String name,
    String? categoryUuid,
    String? brandUuid,
    required int costPriceMinorUnits,
    required int salePriceMinorUnits,
    double taxRatePercent = 0,
    int openingStock = 0,
    int reorderLevel = 0,
    String createdBy = 'system',
  }) async {
    final now = DateTime.now();
    final product = Product(
      uuid: _uuid.v4(),
      businessId: businessId,
      sku: sku,
      name: name,
      categoryUuid: categoryUuid,
      brandUuid: brandUuid,
      costPriceMinorUnits: costPriceMinorUnits,
      salePriceMinorUnits: salePriceMinorUnits,
      taxRatePercent: taxRatePercent,
      stockQuantity: openingStock,
      reorderLevel: reorderLevel,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(Product.tableName, product.toMap());
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        db,
        businessId: businessId,
        entityType: 'Product',
        entityId: product.uuid,
        operation: SyncOperation.create,
      );
    }
    await auditLog?.log(
      businessId: businessId,
      action: 'create',
      entityType: 'Product',
      entityId: product.uuid,
      performedBy: createdBy,
      details: '$sku — $name',
    );
    return product;
  }

  Future<List<Product>> list({required String businessId, bool activeOnly = true}) async {
    final rows = await db.query(
      Product.tableName,
      where: activeOnly ? 'business_id = ? AND is_active = 1' : 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> search({required String businessId, required String query}) async {
    final rows = await db.query(
      Product.tableName,
      where: 'business_id = ? AND is_active = 1 AND (name LIKE ? OR sku LIKE ?)',
      whereArgs: [businessId, '%$query%', '%$query%'],
      orderBy: 'name ASC',
      limit: 25,
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> findByUuid(String uuid) async {
    final rows = await db.query(Product.tableName, where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Adjusts stock and records the movement atomically — every stock
  /// change in the system goes through this, never a bare UPDATE on
  /// `products.stock_quantity`. Call inside the same `db.transaction`
  /// as the related JournalEntry insert so a crash can't leave inventory
  /// and accounting out of sync.
  Future<void> adjustStock(
    DatabaseExecutor txn, {
    required String businessId,
    required String productUuid,
    required int quantityChange,
    required StockMovementReason reason,
    required String sourceType,
    required String sourceId,
  }) async {
    final rows = await txn.query(Product.tableName, where: 'uuid = ?', whereArgs: [productUuid], limit: 1);
    if (rows.isEmpty) throw StateError('Product $productUuid not found');
    final current = Product.fromMap(rows.first);

    await txn.update(
      Product.tableName,
      current.copyWith(stockQuantity: current.stockQuantity + quantityChange).toMap(),
      where: 'uuid = ?',
      whereArgs: [productUuid],
    );

    final movementUuid = _uuid.v4();
    await txn.insert(
      StockMovement.tableName,
      StockMovement(
        uuid: movementUuid,
        businessId: businessId,
        productUuid: productUuid,
        reason: reason,
        quantityChange: quantityChange,
        sourceType: sourceType,
        sourceId: sourceId,
        createdAt: DateTime.now(),
      ).toMap(),
    );
    if (syncQueue != null) {
      await syncQueue!.enqueue(
        txn,
        businessId: businessId,
        entityType: 'StockMovement',
        entityId: movementUuid,
        operation: SyncOperation.create,
      );
    }
  }
}
