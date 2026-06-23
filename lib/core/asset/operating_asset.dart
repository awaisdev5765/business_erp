enum OperatingAssetType { boat, vehicle }

/// A Boat and a Vehicle are both "an asset that generates trips and
/// consumes expenses" — same fields, different `type`. Unifying them here
/// is what makes adding the Transport vertical's Vehicles in Phase 4 a
/// matter of a new enum value, not a new table/screen set. See PHASES.md
/// Section 6/12.
class OperatingAsset {
  OperatingAsset({
    required this.uuid,
    required this.businessId,
    required this.type,
    required this.name,
    this.registrationNumber,
    this.isActive = true,
  });

  final String uuid;
  final String businessId;
  final OperatingAssetType type;
  final String name;

  /// Boat registration number / vehicle plate number.
  final String? registrationNumber;
  final bool isActive;

  static const tableName = 'operating_assets';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      registration_number TEXT,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_operating_assets_business_type ON $tableName (business_id, type)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'type': type.name,
        'name': name,
        'registration_number': registrationNumber,
        'is_active': isActive ? 1 : 0,
      };

  factory OperatingAsset.fromMap(Map<String, Object?> map) => OperatingAsset(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        type: OperatingAssetType.values.byName(map['type'] as String),
        name: map['name'] as String,
        registrationNumber: map['registration_number'] as String?,
        isActive: (map['is_active'] as int) == 1,
      );
}
