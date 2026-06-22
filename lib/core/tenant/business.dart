enum BusinessType { sparePartsShop, fishery, transport }

class Business {
  Business({
    required this.uuid,
    required this.name,
    required this.type,
    this.baseCurrency,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uuid;
  final String name;
  final BusinessType type;

  /// Single-currency for MVP — see PHASES.md Phase 2 for multi-currency.
  final String? baseCurrency;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const tableName = 'businesses';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      base_currency TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'name': name,
        'type': type.name,
        'base_currency': baseCurrency,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Business.fromMap(Map<String, Object?> map) => Business(
        uuid: map['uuid'] as String,
        name: map['name'] as String,
        type: BusinessType.values.byName(map['type'] as String),
        baseCurrency: map['base_currency'] as String?,
        isActive: (map['is_active'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
