/// One Company Bills row: date, vehicle, weight (kg), company.
/// No money is posted here. Month Hisaab multiplies kg × rate/ton.
class WeightEntry {
  WeightEntry({
    required this.uuid,
    required this.businessId,
    required this.vehicleUuid,
    required this.companyUuid,
    required this.date,
    required this.weightKg,
    this.notes,
    this.settlementUuid,
    this.amountMinorUnits,
  });

  final String uuid;
  final String businessId;
  final String vehicleUuid;
  final String companyUuid;
  final DateTime date;
  final double weightKg;
  final String? notes;
  final String? settlementUuid;
  final int? amountMinorUnits;

  bool get isSettled => settlementUuid != null;

  static const tableName = 'weight_entries';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      vehicle_uuid TEXT NOT NULL,
      company_uuid TEXT NOT NULL,
      date TEXT NOT NULL,
      weight_kg REAL NOT NULL,
      notes TEXT,
      settlement_uuid TEXT,
      amount_minor_units INTEGER
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_weight_entries_business_date ON $tableName (business_id, date)';
  static const createVehicleIndexSql =
      'CREATE INDEX idx_weight_entries_vehicle ON $tableName (vehicle_uuid, date)';
  static const createCompanyIndexSql =
      'CREATE INDEX idx_weight_entries_company ON $tableName (company_uuid, date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'vehicle_uuid': vehicleUuid,
        'company_uuid': companyUuid,
        'date': date.toIso8601String(),
        'weight_kg': weightKg,
        'notes': notes,
        'settlement_uuid': settlementUuid,
        'amount_minor_units': amountMinorUnits,
      };

  factory WeightEntry.fromMap(Map<String, Object?> map) {
    final kg = map['weight_kg'] as num?;
    final tons = map['weight_tons'] as num?;
    return WeightEntry(
      uuid: map['uuid'] as String,
      businessId: map['business_id'] as String,
      vehicleUuid: map['vehicle_uuid'] as String,
      companyUuid: map['company_uuid'] as String,
      date: DateTime.parse(map['date'] as String),
      weightKg: (kg ?? ((tons ?? 0) * 1000)).toDouble(),
      notes: map['notes'] as String?,
      settlementUuid: map['settlement_uuid'] as String?,
      amountMinorUnits: map['amount_minor_units'] as int?,
    );
  }
}
