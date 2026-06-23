/// `employee` is a generic role for paid staff who aren't already
/// Captain/Crew/Driver (Cashier, Accountant, Store Keeper, Manager) —
/// see PHASES.md Phase 7. Salary records work for *any* PartyType,
/// including Captain/Crew/Driver, since they need salaries too.
enum PartyType { customer, supplier, captain, crew, driver, employee }

/// A Customer and a Supplier are both "a counterparty with a ledger" — same
/// fields, different `type` and default account mapping. Unifying them
/// here avoids duplicating screens/repositories, and is what lets the
/// Fishery/Transport verticals reuse this for Drivers/Captains later
/// without a new table. See PHASES.md Section 6/11.
class Party {
  Party({
    required this.uuid,
    required this.businessId,
    required this.type,
    required this.name,
    this.phone,
    this.address,
    this.creditLimitMinorUnits,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uuid;
  final String businessId;
  final PartyType type;
  final String name;
  final String? phone;
  final String? address;

  /// Only meaningful for customers; null = no limit enforced.
  final int? creditLimitMinorUnits;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const tableName = 'parties';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      phone TEXT,
      address TEXT,
      credit_limit_minor_units INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_parties_business_type ON $tableName (business_id, type)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'type': type.name,
        'name': name,
        'phone': phone,
        'address': address,
        'credit_limit_minor_units': creditLimitMinorUnits,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Party.fromMap(Map<String, Object?> map) => Party(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        type: PartyType.values.byName(map['type'] as String),
        name: map['name'] as String,
        phone: map['phone'] as String?,
        address: map['address'] as String?,
        creditLimitMinorUnits: map['credit_limit_minor_units'] as int?,
        isActive: (map['is_active'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Party copyWith({
    String? name,
    String? phone,
    String? address,
    int? creditLimitMinorUnits,
    bool? isActive,
  }) =>
      Party(
        uuid: uuid,
        businessId: businessId,
        type: type,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        creditLimitMinorUnits: creditLimitMinorUnits ?? this.creditLimitMinorUnits,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
