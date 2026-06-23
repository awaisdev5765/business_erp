/// A named tax rate a business can apply to products (e.g. "Standard
/// VAT 15%", "Zero-rated 0%"). Products store their own `taxRatePercent`
/// (see Product) rather than a foreign key here — this table exists so
/// the rates have names/management UI and so a future Tax Summary report
/// can group by named rate instead of a bare percentage. See PHASES.md
/// Section 2 ("Tax handling").
class TaxRate {
  TaxRate({
    required this.uuid,
    required this.businessId,
    required this.name,
    required this.ratePercent,
    this.isActive = true,
  });

  final String uuid;
  final String businessId;
  final String name;
  final double ratePercent;
  final bool isActive;

  static const tableName = 'tax_rates';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      name TEXT NOT NULL,
      rate_percent REAL NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'name': name,
        'rate_percent': ratePercent,
        'is_active': isActive ? 1 : 0,
      };

  factory TaxRate.fromMap(Map<String, Object?> map) => TaxRate(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        name: map['name'] as String,
        ratePercent: (map['rate_percent'] as num).toDouble(),
        isActive: (map['is_active'] as int) == 1,
      );
}
