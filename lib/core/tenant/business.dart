enum BusinessType { sparePartsShop, fishery, transport }

class Business {
  Business({
    required this.uuid,
    required this.name,
    required this.type,
    this.baseCurrency,
    this.address,
    this.phone,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uuid;
  final String name;
  final BusinessType type;

  /// Single-currency for MVP — see PHASES.md Phase 2 for multi-currency.
  /// Set by the Super Admin when creating (or later editing) a business
  /// — see BusinessSwitcherScreen and shared/currency/currency.dart.
  final String? baseCurrency;

  /// Shown on receipts/invoices alongside the business name. Both
  /// optional — existed nowhere in the model before, so every receipt
  /// only ever had a name with no way to add contact details.
  final String? address;
  final String? phone;

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
      address TEXT,
      phone TEXT,
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
        'address': address,
        'phone': phone,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Business.fromMap(Map<String, Object?> map) => Business(
        uuid: map['uuid'] as String,
        name: map['name'] as String,
        type: BusinessType.values.byName(map['type'] as String),
        baseCurrency: map['base_currency'] as String?,
        address: map['address'] as String?,
        phone: map['phone'] as String?,
        isActive: (map['is_active'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Business copyWith({
    String? name,
    String? baseCurrency,
    String? address,
    String? phone,
  }) => Business(
        uuid: uuid,
        name: name ?? this.name,
        type: type,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
