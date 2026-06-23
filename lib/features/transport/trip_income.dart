enum TripIncomePaymentMethod { cash, credit }

/// Revenue from a transport trip — the Transport-vertical counterpart to
/// FishSale, posting to the same shared Trip/Catch Income account (4020)
/// since both are "revenue from running a trip." No COGS posting, same
/// reasoning as FishSale: the trip's operating cost is already expensed
/// via TripExpense (fuel/maintenance/repair/tyre/oil), so Vehicle/Trip
/// profitability is revenue minus expenses directly. See PHASES.md
/// Section 6.
class TripIncome {
  TripIncome({
    required this.uuid,
    required this.businessId,
    required this.tripUuid,
    this.customerUuid,
    this.contractUuid,
    required this.amountMinorUnits,
    this.description,
    required this.paymentMethod,
    required this.date,
  });

  final String uuid;
  final String businessId;
  final String tripUuid;
  final String? customerUuid;

  /// Optional traceability link to the standing agreement this trip
  /// fulfilled — see Contract's doc comment. Not required.
  final String? contractUuid;
  final int amountMinorUnits;
  final String? description;
  final TripIncomePaymentMethod paymentMethod;
  final DateTime date;

  static const tableName = 'trip_incomes';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      trip_uuid TEXT NOT NULL,
      customer_uuid TEXT,
      contract_uuid TEXT,
      amount_minor_units INTEGER NOT NULL,
      description TEXT,
      payment_method TEXT NOT NULL,
      date TEXT NOT NULL
    )
  ''';

  static const createIndexSql = 'CREATE INDEX idx_trip_incomes_trip ON $tableName (trip_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'trip_uuid': tripUuid,
        'customer_uuid': customerUuid,
        'contract_uuid': contractUuid,
        'amount_minor_units': amountMinorUnits,
        'description': description,
        'payment_method': paymentMethod.name,
        'date': date.toIso8601String(),
      };

  factory TripIncome.fromMap(Map<String, Object?> map) => TripIncome(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        tripUuid: map['trip_uuid'] as String,
        customerUuid: map['customer_uuid'] as String?,
        contractUuid: map['contract_uuid'] as String?,
        amountMinorUnits: map['amount_minor_units'] as int,
        description: map['description'] as String?,
        paymentMethod: TripIncomePaymentMethod.values.byName(map['payment_method'] as String),
        date: DateTime.parse(map['date'] as String),
      );
}
