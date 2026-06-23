enum TripExpenseCategory { fuel, ice, food, maintenance, other }

/// Maps each category to its Chart of Accounts code — see
/// chart_of_accounts_seed.dart for the seeded expense accounts.
const Map<TripExpenseCategory, String> tripExpenseAccountCode = {
  TripExpenseCategory.fuel: '5020',
  TripExpenseCategory.ice: '5040',
  TripExpenseCategory.food: '5045',
  TripExpenseCategory.maintenance: '5030',
  TripExpenseCategory.other: '5050',
};

/// One expense logged against a trip — posts Dr (category account) / Cr
/// Cash(1010), tagged with the trip's boat as the journal line's
/// `dimensionUuid` so it surfaces in the Boat Ledger (a filtered view over
/// `journal_lines.dimension_uuid`, same pattern as the Customer/Supplier
/// Ledger over `party_uuid`). See PHASES.md Section 11.
class TripExpense {
  TripExpense({
    required this.uuid,
    required this.tripUuid,
    required this.businessId,
    required this.category,
    required this.amountMinorUnits,
    this.description,
    required this.date,
  });

  final String uuid;
  final String tripUuid;
  final String businessId;
  final TripExpenseCategory category;
  final int amountMinorUnits;
  final String? description;
  final DateTime date;

  static const tableName = 'trip_expenses';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      trip_uuid TEXT NOT NULL,
      business_id TEXT NOT NULL,
      category TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      description TEXT,
      date TEXT NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_trip_expenses_trip ON $tableName (trip_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'trip_uuid': tripUuid,
        'business_id': businessId,
        'category': category.name,
        'amount_minor_units': amountMinorUnits,
        'description': description,
        'date': date.toIso8601String(),
      };

  factory TripExpense.fromMap(Map<String, Object?> map) => TripExpense(
        uuid: map['uuid'] as String,
        tripUuid: map['trip_uuid'] as String,
        businessId: map['business_id'] as String,
        category: TripExpenseCategory.values.byName(map['category'] as String),
        amountMinorUnits: map['amount_minor_units'] as int,
        description: map['description'] as String?,
        date: DateTime.parse(map['date'] as String),
      );
}
