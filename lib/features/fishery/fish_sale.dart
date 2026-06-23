enum FishSalePaymentMethod { cash, credit }

/// Revenue from selling a trip's catch. Unlike SaleRepository (spare
/// parts), there's no COGS/Inventory posting here — the catch's "cost"
/// was already expensed when it was caught (fuel/ice/food/maintenance via
/// TripExpense), so Trip Profit is simply catch revenue minus trip
/// expenses, not a per-unit cost calculation. See PHASES.md Section 6.
class FishSale {
  FishSale({
    required this.uuid,
    required this.businessId,
    required this.tripUuid,
    this.customerUuid,
    required this.fishCategoryUuid,
    required this.weightKg,
    required this.unitPriceMinorUnitsPerKg,
    required this.paymentMethod,
    required this.date,
  });

  final String uuid;
  final String businessId;
  final String tripUuid;
  final String? customerUuid;
  final String fishCategoryUuid;
  final double weightKg;
  final int unitPriceMinorUnitsPerKg;
  final FishSalePaymentMethod paymentMethod;
  final DateTime date;

  int get totalMinorUnits => (weightKg * unitPriceMinorUnitsPerKg).round();

  static const tableName = 'fish_sales';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      trip_uuid TEXT NOT NULL,
      customer_uuid TEXT,
      fish_category_uuid TEXT NOT NULL,
      weight_kg REAL NOT NULL,
      unit_price_minor_units_per_kg INTEGER NOT NULL,
      payment_method TEXT NOT NULL,
      date TEXT NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_fish_sales_trip ON $tableName (trip_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'trip_uuid': tripUuid,
        'customer_uuid': customerUuid,
        'fish_category_uuid': fishCategoryUuid,
        'weight_kg': weightKg,
        'unit_price_minor_units_per_kg': unitPriceMinorUnitsPerKg,
        'payment_method': paymentMethod.name,
        'date': date.toIso8601String(),
      };

  factory FishSale.fromMap(Map<String, Object?> map) => FishSale(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        tripUuid: map['trip_uuid'] as String,
        customerUuid: map['customer_uuid'] as String?,
        fishCategoryUuid: map['fish_category_uuid'] as String,
        weightKg: (map['weight_kg'] as num).toDouble(),
        unitPriceMinorUnitsPerKg: map['unit_price_minor_units_per_kg'] as int,
        paymentMethod: FishSalePaymentMethod.values.byName(map['payment_method'] as String),
        date: DateTime.parse(map['date'] as String),
      );
}
