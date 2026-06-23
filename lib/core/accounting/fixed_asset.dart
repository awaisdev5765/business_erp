/// A depreciable fixed asset. [operatingAssetUuid] is optional — when set,
/// this *is* a Boat/Vehicle from the OperatingAsset registry (PHASES.md
/// Section 6/12: those are literally fixed assets that depreciate, not a
/// separate concept); when null, this is some other piece of equipment
/// (e.g. shop fixtures) that never needed an OperatingAsset entry because
/// it doesn't generate Trips.
class FixedAsset {
  FixedAsset({
    required this.uuid,
    required this.businessId,
    required this.name,
    this.operatingAssetUuid,
    required this.acquisitionDate,
    required this.acquisitionCostMinorUnits,
    required this.usefulLifeMonths,
    this.salvageValueMinorUnits = 0,
    this.isActive = true,
  });

  final String uuid;
  final String businessId;
  final String name;
  final String? operatingAssetUuid;
  final DateTime acquisitionDate;
  final int acquisitionCostMinorUnits;
  final int usefulLifeMonths;
  final int salvageValueMinorUnits;
  final bool isActive;

  /// Straight-line monthly depreciation — (cost - salvage) / life.
  /// Integer division means the last month absorbs any rounding
  /// remainder rather than the schedule running slightly short — see
  /// DepreciationService.postMonthlyDepreciation().
  int get monthlyDepreciationMinorUnits =>
      (acquisitionCostMinorUnits - salvageValueMinorUnits) ~/ usefulLifeMonths;

  static const tableName = 'fixed_assets';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      name TEXT NOT NULL,
      operating_asset_uuid TEXT,
      acquisition_date TEXT NOT NULL,
      acquisition_cost_minor_units INTEGER NOT NULL,
      useful_life_months INTEGER NOT NULL,
      salvage_value_minor_units INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_fixed_assets_business ON $tableName (business_id)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'name': name,
        'operating_asset_uuid': operatingAssetUuid,
        'acquisition_date': acquisitionDate.toIso8601String(),
        'acquisition_cost_minor_units': acquisitionCostMinorUnits,
        'useful_life_months': usefulLifeMonths,
        'salvage_value_minor_units': salvageValueMinorUnits,
        'is_active': isActive ? 1 : 0,
      };

  factory FixedAsset.fromMap(Map<String, Object?> map) => FixedAsset(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        operatingAssetUuid: map['operating_asset_uuid'] as String?,
        acquisitionDate: DateTime.parse(map['acquisition_date'] as String),
        acquisitionCostMinorUnits: map['acquisition_cost_minor_units'] as int,
        usefulLifeMonths: map['useful_life_months'] as int,
        salvageValueMinorUnits: map['salvage_value_minor_units'] as int,
        isActive: (map['is_active'] as int) == 1,
      );
}

/// One posted month of depreciation for a [FixedAsset] — the record that
/// prevents double-posting the same asset/month twice (unique on
/// `(fixed_asset_uuid, period)`), and what `bookValue()` sums against the
/// acquisition cost.
class DepreciationEntry {
  DepreciationEntry({
    required this.uuid,
    required this.fixedAssetUuid,
    required this.businessId,
    required this.period,
    required this.amountMinorUnits,
    required this.postedAt,
  });

  final String uuid;
  final String fixedAssetUuid;
  final String businessId;

  /// "YYYY-MM" — one row per asset per calendar month.
  final String period;
  final int amountMinorUnits;
  final DateTime postedAt;

  static const tableName = 'depreciation_entries';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      fixed_asset_uuid TEXT NOT NULL,
      business_id TEXT NOT NULL,
      period TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      posted_at TEXT NOT NULL,
      UNIQUE (fixed_asset_uuid, period)
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_depreciation_entries_asset ON $tableName (fixed_asset_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'fixed_asset_uuid': fixedAssetUuid,
        'business_id': businessId,
        'period': period,
        'amount_minor_units': amountMinorUnits,
        'posted_at': postedAt.toIso8601String(),
      };

  factory DepreciationEntry.fromMap(Map<String, Object?> map) => DepreciationEntry(
        uuid: map['uuid'] as String,
        fixedAssetUuid: map['fixed_asset_uuid'] as String,
        businessId: map['business_id'] as String,
        period: map['period'] as String,
        amountMinorUnits: map['amount_minor_units'] as int,
        postedAt: DateTime.parse(map['posted_at'] as String),
      );
}
