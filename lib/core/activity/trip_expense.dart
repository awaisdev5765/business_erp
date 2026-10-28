/// Shared across Fishery and Transport trips — ice/food apply to fishery,
/// repair/tyre/oil apply to transport, fuel/maintenance/other apply to
/// both. The UI filters which categories it offers based on the trip's
/// `tripType` (see [tripExpenseCategoriesByTripType]); the backend
/// doesn't need to know or care which vertical a category "belongs to".
enum TripExpenseCategory { fuel, ice, food, maintenance, repair, tyre, oil, other }

/// Maps each category to its Chart of Accounts code — see
/// chart_of_accounts_seed.dart for the seeded expense accounts.
const Map<TripExpenseCategory, String> tripExpenseAccountCode = {
  TripExpenseCategory.fuel: '5020',
  TripExpenseCategory.ice: '5040',
  TripExpenseCategory.food: '5045',
  TripExpenseCategory.maintenance: '5030',
  TripExpenseCategory.repair: '5060',
  TripExpenseCategory.tyre: '5070',
  TripExpenseCategory.oil: '5080',
  TripExpenseCategory.other: '5050',
};

/// Which categories are relevant to which vertical — used to filter the
/// expense-category dropdown in the UI per trip type (keyed by
/// `TripType.name` to avoid a core/activity -> core/activity self-import).
const Map<String, List<TripExpenseCategory>> tripExpenseCategoriesByTripType = {
  'fishery': [
    TripExpenseCategory.fuel,
    TripExpenseCategory.ice,
    TripExpenseCategory.food,
    TripExpenseCategory.maintenance,
    TripExpenseCategory.other,
  ],
  'transport': [
    TripExpenseCategory.fuel,
    TripExpenseCategory.maintenance,
    TripExpenseCategory.repair,
    TripExpenseCategory.tyre,
    TripExpenseCategory.oil,
    TripExpenseCategory.other,
  ],
};

/// One expense logged against a trip — posts Dr (category account) / Cr
/// Cash(1010), tagged with the trip's boat as the journal line's
/// `dimensionUuid` so it surfaces in the Boat Ledger (a filtered view over
/// `journal_lines.dimension_uuid`, same pattern as the Customer/Supplier
/// Ledger over `party_uuid`). See PHASES.md Section 11.
class TripExpense {
  TripExpense({
    required this.uuid,
    this.tripUuid,
    this.assetUuid,
    required this.businessId,
    required this.category,
    required this.amountMinorUnits,
    this.description,
    required this.date,
  });

  final String uuid;

  /// Fishery (and old transport trips) still attach expenses to a trip.
  /// Vehicle khata expenses have no trip — only [assetUuid].
  final String? tripUuid;

  /// Boat/vehicle this expense belongs to. Set for new rows so vehicle
  /// khata works without going through a trip.
  final String? assetUuid;
  final String businessId;
  final TripExpenseCategory category;
  final int amountMinorUnits;
  final String? description;
  final DateTime date;

  static const tableName = 'trip_expenses';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      trip_uuid TEXT,
      asset_uuid TEXT,
      business_id TEXT NOT NULL,
      category TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      description TEXT,
      date TEXT NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_trip_expenses_trip ON $tableName (trip_uuid)';
  static const createAssetIndexSql = 'CREATE INDEX idx_trip_expenses_asset ON $tableName (asset_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'trip_uuid': tripUuid,
        'asset_uuid': assetUuid,
        'business_id': businessId,
        'category': category.name,
        'amount_minor_units': amountMinorUnits,
        'description': description,
        'date': date.toIso8601String(),
      };

  factory TripExpense.fromMap(Map<String, Object?> map) => TripExpense(
        uuid: map['uuid'] as String,
        tripUuid: map['trip_uuid'] as String?,
        assetUuid: map['asset_uuid'] as String?,
        businessId: map['business_id'] as String,
        category: TripExpenseCategory.values.byName(map['category'] as String),
        amountMinorUnits: map['amount_minor_units'] as int,
        description: map['description'] as String?,
        date: DateTime.parse(map['date'] as String),
      );
}
