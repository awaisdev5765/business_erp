/// A registry of the business's actual bank accounts. Money movement
/// through a bank still posts to the generic "1020 Bank Accounts" GL
/// account for now (Sales/Payments don't yet let you pick a specific bank
/// account as the cash leg — that's a Phase 3+ follow-up); this model and
/// [BankStatementLine] exist so a Bank Reconciliation workflow can start
/// now, tracked independently of that deeper posting integration.
class BankAccount {
  BankAccount({
    required this.uuid,
    required this.businessId,
    required this.name,
    this.bankName,
    this.accountNumber,
    this.openingBalanceMinorUnits = 0,
    this.isActive = true,
  });

  final String uuid;
  final String businessId;
  final String name;
  final String? bankName;
  final String? accountNumber;
  final int openingBalanceMinorUnits;
  final bool isActive;

  static const tableName = 'bank_accounts';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      name TEXT NOT NULL,
      bank_name TEXT,
      account_number TEXT,
      opening_balance_minor_units INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'name': name,
        'bank_name': bankName,
        'account_number': accountNumber,
        'opening_balance_minor_units': openingBalanceMinorUnits,
        'is_active': isActive ? 1 : 0,
      };

  factory BankAccount.fromMap(Map<String, Object?> map) => BankAccount(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        bankName: map['bank_name'] as String?,
        accountNumber: map['account_number'] as String?,
        openingBalanceMinorUnits: map['opening_balance_minor_units'] as int,
        isActive: (map['is_active'] as int) == 1,
      );
}

/// One line of a bank statement, entered manually (CSV/OFX import is a
/// later addition — see PHASES.md Phase 2 roadmap). Reconciliation =
/// comparing the running total of [isCleared] lines against the
/// statement's stated closing balance for the same period.
class BankStatementLine {
  BankStatementLine({
    required this.uuid,
    required this.bankAccountUuid,
    required this.date,
    required this.description,
    required this.amountMinorUnits,
    this.isCleared = false,
  });

  final String uuid;
  final String bankAccountUuid;
  final DateTime date;
  final String description;

  /// Signed: positive = deposit, negative = withdrawal.
  final int amountMinorUnits;
  final bool isCleared;

  static const tableName = 'bank_statement_lines';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      bank_account_uuid TEXT NOT NULL,
      date TEXT NOT NULL,
      description TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      is_cleared INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_bank_statement_lines_account ON $tableName (bank_account_uuid, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'bank_account_uuid': bankAccountUuid,
        'date': date.toIso8601String(),
        'description': description,
        'amount_minor_units': amountMinorUnits,
        'is_cleared': isCleared ? 1 : 0,
      };

  factory BankStatementLine.fromMap(Map<String, Object?> map) => BankStatementLine(
        uuid: map['uuid'] as String,
        bankAccountUuid: map['bank_account_uuid'] as String,
        date: DateTime.parse(map['date'] as String),
        description: map['description'] as String,
        amountMinorUnits: map['amount_minor_units'] as int,
        isCleared: (map['is_cleared'] as int) == 1,
      );
}
