class Category {
  Category({
    required this.uuid,
    required this.businessId,
    required this.name,
    this.isActive = true,
  });

  final String uuid;
  final String businessId;
  final String name;
  final bool isActive;

  static const tableName = 'categories';

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

  factory Category.fromMap(Map<String, Object?> map) => Category(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        isActive: (map['is_active'] as int) == 1,
      );
}

class Brand {
  Brand({
    required this.uuid,
    required this.businessId,
    required this.name,
    this.isActive = true,
  });

  final String uuid;
  final String businessId;
  final String name;
  final bool isActive;

  static const tableName = 'brands';

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

  factory Brand.fromMap(Map<String, Object?> map) => Brand(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        isActive: (map['is_active'] as int) == 1,
      );
}
