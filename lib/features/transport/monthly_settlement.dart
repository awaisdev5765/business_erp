/// Month-end hisaab for one company: total weight × rate = bill.
/// Posts Dr Receivable (company khata) / Cr Trip Income split across
/// vehicles so each vehicle khata sees its share. See WeightEntry.
class MonthlySettlement {
  MonthlySettlement({
    required this.uuid,
    required this.businessId,
    required this.companyUuid,
    required this.year,
    required this.month,
    required this.ratePerTonMinorUnits,
    required this.totalWeightKg,
    required this.amountMinorUnits,
    required this.date,
  });

  final String uuid;
  final String businessId;
  final String companyUuid;
  final int year;
  final int month;
  final int ratePerTonMinorUnits;
  final double totalWeightKg;
  final int amountMinorUnits;
  final DateTime date;

  static const tableName = 'monthly_settlements';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      company_uuid TEXT NOT NULL,
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      rate_per_ton_minor_units INTEGER NOT NULL,
      total_weight_kg REAL NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      date TEXT NOT NULL,
      UNIQUE (business_id, company_uuid, year, month)
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_monthly_settlements_business ON $tableName (business_id, year, month)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'company_uuid': companyUuid,
        'year': year,
        'month': month,
        'rate_per_ton_minor_units': ratePerTonMinorUnits,
        'total_weight_kg': totalWeightKg,
        'amount_minor_units': amountMinorUnits,
        'date': date.toIso8601String(),
      };

  factory MonthlySettlement.fromMap(Map<String, Object?> map) => MonthlySettlement(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        companyUuid: map['company_uuid'] as String,
        year: map['year'] as int,
        month: map['month'] as int,
        ratePerTonMinorUnits: map['rate_per_ton_minor_units'] as int,
        totalWeightKg: ((map['total_weight_kg'] as num?) ??
                ((map['total_weight_tons'] as num?) ?? 0) * 1000)
            .toDouble(),
        amountMinorUnits: map['amount_minor_units'] as int,
        date: DateTime.parse(map['date'] as String),
      );
}
