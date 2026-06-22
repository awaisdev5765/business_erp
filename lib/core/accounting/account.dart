enum AccountType { asset, liability, equity, income, expense }

class Account {
  Account({
    required this.uuid,
    required this.businessId,
    required this.code,
    required this.name,
    required this.type,
    this.parentCode,
    this.isActive = true,
    this.isSystemAccount = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uuid;
  final String businessId;

  /// e.g. "1010" — matches the seeded Chart of Accounts.
  final String code;
  final String name;
  final AccountType type;

  /// Optional parent account code for grouping (e.g. "1000" Assets > "1010" Cash).
  final String? parentCode;

  final bool isActive;
  final bool isSystemAccount; // seeded accounts users shouldn't delete
  final DateTime createdAt;
  final DateTime updatedAt;

  static const tableName = 'accounts';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      parent_code TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_system_account INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (business_id, code)
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_accounts_business ON $tableName (business_id, code)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'code': code,
        'name': name,
        'type': type.name,
        'parent_code': parentCode,
        'is_active': isActive ? 1 : 0,
        'is_system_account': isSystemAccount ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Account.fromMap(Map<String, Object?> map) => Account(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        code: map['code'] as String,
        name: map['name'] as String,
        type: AccountType.values.byName(map['type'] as String),
        parentCode: map['parent_code'] as String?,
        isActive: (map['is_active'] as int) == 1,
        isSystemAccount: (map['is_system_account'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
