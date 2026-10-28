/// Company rate card — typically Rs per ton. Used at month-end hisaab
/// (weight × rate). Old [ratePerTripMinorUnits] is kept for existing rows
/// only; new UI writes [ratePerTonMinorUnits]. Company khata itself is
/// still the Customer Ledger.
class Contract {
  Contract({
    required this.uuid,
    required this.businessId,
    required this.customerUuid,
    required this.description,
    this.ratePerTripMinorUnits,
    this.ratePerTonMinorUnits,
    this.isActive = true,
    required this.startDate,
    this.endDate,
  });

  final String uuid;
  final String businessId;
  final String customerUuid;
  final String description;
  final int? ratePerTripMinorUnits;
  final int? ratePerTonMinorUnits;
  final bool isActive;
  final DateTime startDate;
  final DateTime? endDate;

  static const tableName = 'contracts';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      customer_uuid TEXT NOT NULL,
      description TEXT NOT NULL,
      rate_per_trip_minor_units INTEGER,
      rate_per_ton_minor_units INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1,
      start_date TEXT NOT NULL,
      end_date TEXT
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_contracts_business ON $tableName (business_id, customer_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'customer_uuid': customerUuid,
        'description': description,
        'rate_per_trip_minor_units': ratePerTripMinorUnits,
        'rate_per_ton_minor_units': ratePerTonMinorUnits,
        'is_active': isActive ? 1 : 0,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
      };

  factory Contract.fromMap(Map<String, Object?> map) => Contract(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        customerUuid: map['customer_uuid'] as String,
        description: map['description'] as String,
        ratePerTripMinorUnits: map['rate_per_trip_minor_units'] as int?,
        ratePerTonMinorUnits: map['rate_per_ton_minor_units'] as int?,
        isActive: (map['is_active'] as int) == 1,
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: map['end_date'] != null ? DateTime.parse(map['end_date'] as String) : null,
      );
}
