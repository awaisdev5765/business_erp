enum FiscalPeriodStatus { open, closed, locked }

/// A book-closing boundary. Once a period is Closed, new postings dated
/// inside it are rejected — corrections become reversing entries dated in
/// the *current* open period, never edits to the past. Locked periods are
/// the same but additionally protected from being re-opened by a regular
/// Business Admin (only relevant once roles enforce it — see PHASES.md
/// Section 7/11).
class FiscalPeriod {
  FiscalPeriod({
    required this.uuid,
    required this.businessId,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  final String uuid;
  final String businessId;
  final DateTime startDate;
  final DateTime endDate;
  final FiscalPeriodStatus status;

  static const tableName = 'fiscal_periods';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      status TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_fiscal_periods_business ON $tableName (business_id, start_date, end_date)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'status': status.name,
      };

  factory FiscalPeriod.fromMap(Map<String, Object?> map) => FiscalPeriod(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: DateTime.parse(map['end_date'] as String),
        status: FiscalPeriodStatus.values.byName(map['status'] as String),
      );
}
