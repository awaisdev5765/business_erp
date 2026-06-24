enum ExpensePaymentMethod { cash, bankTransfer, cheque, card, other }

/// A general business expense (rent, utilities, miscellaneous) — posts
/// Dr {expense account} / Cr Cash-or-Bank. Until now the only way to
/// post to an expense account at all was indirectly, through Payroll
/// (Salary Expense) or a Fishery/Transport TripExpense — a Spare Parts
/// shop (or any business's plain overhead, outside a trip) had no way
/// to record an expense whatsoever.
class Expense {
  Expense({
    required this.uuid,
    required this.businessId,
    required this.accountCode,
    required this.amountMinorUnits,
    this.description,
    this.method = ExpensePaymentMethod.cash,
    required this.date,
    required this.createdBy,
    required this.createdAt,
  });

  final String uuid;
  final String businessId;

  /// Which expense account this hits — e.g. "5120" Rent Expense. Reuses
  /// the existing Chart of Accounts rather than inventing a separate
  /// "expense category" entity; an expense account already *is* a
  /// category.
  final String accountCode;
  final int amountMinorUnits;
  final String? description;
  final ExpensePaymentMethod method;
  final DateTime date;
  final String createdBy;
  final DateTime createdAt;

  static const tableName = 'expenses';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      account_code TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      description TEXT,
      method TEXT NOT NULL DEFAULT 'cash',
      date TEXT NOT NULL,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_expenses_business_date ON $tableName (business_id, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'account_code': accountCode,
        'amount_minor_units': amountMinorUnits,
        'description': description,
        'method': method.name,
        'date': date.toIso8601String(),
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };

  factory Expense.fromMap(Map<String, Object?> map) => Expense(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        accountCode: map['account_code'] as String,
        amountMinorUnits: map['amount_minor_units'] as int,
        description: map['description'] as String?,
        method: ExpensePaymentMethod.values.byName(map['method'] as String? ?? 'cash'),
        date: DateTime.parse(map['date'] as String),
        createdBy: map['created_by'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
