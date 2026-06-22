/// Single-warehouse inventory for Phase 1 (see PHASES.md). Multi-warehouse
/// transfer/adjustment is a later addition — `stockQuantity` here is a
/// denormalized running total, kept in sync by [StockMovement] inserts
/// inside the same transaction as every Purchase/Sale/Adjustment posting.
class Product {
  Product({
    required this.uuid,
    required this.businessId,
    required this.sku,
    required this.name,
    this.categoryUuid,
    this.brandUuid,
    required this.costPriceMinorUnits,
    required this.salePriceMinorUnits,
    this.taxRatePercent = 0,
    this.stockQuantity = 0,
    this.reorderLevel = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uuid;
  final String businessId;
  final String sku;
  final String name;
  final String? categoryUuid;
  final String? brandUuid;
  final int costPriceMinorUnits;
  final int salePriceMinorUnits;
  final double taxRatePercent;
  final int stockQuantity;
  final int reorderLevel;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const tableName = 'products';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      sku TEXT NOT NULL,
      name TEXT NOT NULL,
      category_uuid TEXT,
      brand_uuid TEXT,
      cost_price_minor_units INTEGER NOT NULL DEFAULT 0,
      sale_price_minor_units INTEGER NOT NULL DEFAULT 0,
      tax_rate_percent REAL NOT NULL DEFAULT 0,
      stock_quantity INTEGER NOT NULL DEFAULT 0,
      reorder_level INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (business_id, sku)
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_products_business_name ON $tableName (business_id, name)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'sku': sku,
        'name': name,
        'category_uuid': categoryUuid,
        'brand_uuid': brandUuid,
        'cost_price_minor_units': costPriceMinorUnits,
        'sale_price_minor_units': salePriceMinorUnits,
        'tax_rate_percent': taxRatePercent,
        'stock_quantity': stockQuantity,
        'reorder_level': reorderLevel,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<String, Object?> map) => Product(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        sku: map['sku'] as String,
        name: map['name'] as String,
        categoryUuid: map['category_uuid'] as String?,
        brandUuid: map['brand_uuid'] as String?,
        costPriceMinorUnits: map['cost_price_minor_units'] as int,
        salePriceMinorUnits: map['sale_price_minor_units'] as int,
        taxRatePercent: (map['tax_rate_percent'] as num).toDouble(),
        stockQuantity: map['stock_quantity'] as int,
        reorderLevel: map['reorder_level'] as int,
        isActive: (map['is_active'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Product copyWith({int? stockQuantity}) => Product(
        uuid: uuid,
        businessId: businessId,
        sku: sku,
        name: name,
        categoryUuid: categoryUuid,
        brandUuid: brandUuid,
        costPriceMinorUnits: costPriceMinorUnits,
        salePriceMinorUnits: salePriceMinorUnits,
        taxRatePercent: taxRatePercent,
        stockQuantity: stockQuantity ?? this.stockQuantity,
        reorderLevel: reorderLevel,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

enum StockMovementReason { purchase, sale, purchaseReturn, saleReturn, adjustment }

/// Append-only audit trail of every stock change — mirrors the ledger's
/// "never mutate, only append" principle so inventory history is as
/// trustworthy as the accounting history.
class StockMovement {
  StockMovement({
    required this.uuid,
    required this.businessId,
    required this.productUuid,
    required this.reason,
    required this.quantityChange, // signed: +in, -out
    required this.sourceType,
    required this.sourceId,
    required this.createdAt,
  });

  final String uuid;
  final String businessId;
  final String productUuid;
  final StockMovementReason reason;
  final int quantityChange;
  final String sourceType;
  final String sourceId;
  final DateTime createdAt;

  static const tableName = 'stock_movements';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      product_uuid TEXT NOT NULL,
      reason TEXT NOT NULL,
      quantity_change INTEGER NOT NULL,
      source_type TEXT NOT NULL,
      source_id TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_stock_movements_product ON $tableName (product_uuid, created_at)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'product_uuid': productUuid,
        'reason': reason.name,
        'quantity_change': quantityChange,
        'source_type': sourceType,
        'source_id': sourceId,
        'created_at': createdAt.toIso8601String(),
      };

  factory StockMovement.fromMap(Map<String, Object?> map) => StockMovement(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        productUuid: map['product_uuid'] as String,
        reason: StockMovementReason.values.byName(map['reason'] as String),
        quantityChange: map['quantity_change'] as int,
        sourceType: map['source_type'] as String,
        sourceId: map['source_id'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
