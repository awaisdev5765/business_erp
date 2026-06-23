class FishCategory {
  FishCategory({required this.uuid, required this.businessId, required this.name, this.isActive = true});

  final String uuid;
  final String businessId;
  final String name;
  final bool isActive;

  static const tableName = 'fish_categories';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      name TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'name': name,
        'is_active': isActive ? 1 : 0,
      };

  factory FishCategory.fromMap(Map<String, Object?> map) => FishCategory(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        isActive: (map['is_active'] as int) == 1,
      );
}

/// Tracks what a trip caught, before it's sold. Doesn't post any
/// accounting on its own — it's inventory-of-catch awaiting a [FishSale],
/// the same way a Product's stock level isn't revenue until a Sale
/// happens. `estimatedValueMinorUnits` is informational only (for
/// pre-sale trip profit estimates); the real revenue is whatever the
/// FishSale actually posts.
class CatchEntry {
  CatchEntry({
    required this.uuid,
    required this.tripUuid,
    required this.businessId,
    required this.fishCategoryUuid,
    required this.weightKg,
    this.estimatedValueMinorUnits,
  });

  final String uuid;
  final String tripUuid;
  final String businessId;
  final String fishCategoryUuid;
  final double weightKg;
  final int? estimatedValueMinorUnits;

  static const tableName = 'catch_entries';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      trip_uuid TEXT NOT NULL,
      business_id TEXT NOT NULL,
      fish_category_uuid TEXT NOT NULL,
      weight_kg REAL NOT NULL,
      estimated_value_minor_units INTEGER
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_catch_entries_trip ON $tableName (trip_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'trip_uuid': tripUuid,
        'business_id': businessId,
        'fish_category_uuid': fishCategoryUuid,
        'weight_kg': weightKg,
        'estimated_value_minor_units': estimatedValueMinorUnits,
      };

  factory CatchEntry.fromMap(Map<String, Object?> map) => CatchEntry(
        uuid: map['uuid'] as String,
        tripUuid: map['trip_uuid'] as String,
        businessId: map['business_id'] as String,
        fishCategoryUuid: map['fish_category_uuid'] as String,
        weightKg: (map['weight_kg'] as num).toDouble(),
        estimatedValueMinorUnits: map['estimated_value_minor_units'] as int?,
      );
}
