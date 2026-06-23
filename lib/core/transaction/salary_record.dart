/// Standing salary terms for one [Party] (any type — Captain/Crew/Driver
/// need salaries too, not just the generic `employee` role). See
/// PHASES.md Phase 7.
class SalaryRecord {
  SalaryRecord({
    required this.uuid,
    required this.businessId,
    required this.partyUuid,
    required this.amountMinorUnits,
    this.isActive = true,
    required this.startDate,
  });

  final String uuid;
  final String businessId;
  final String partyUuid;

  /// Monthly amount — the only frequency for Phase 7; weekly/biweekly is
  /// future work if a business actually needs it.
  final int amountMinorUnits;
  final bool isActive;
  final DateTime startDate;

  static const tableName = 'salary_records';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      party_uuid TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      start_date TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_salary_records_business ON $tableName (business_id, party_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'business_id': businessId,
        'party_uuid': partyUuid,
        'amount_minor_units': amountMinorUnits,
        'is_active': isActive ? 1 : 0,
        'start_date': startDate.toIso8601String(),
      };

  factory SalaryRecord.fromMap(Map<String, Object?> map) => SalaryRecord(
        uuid: map['uuid'] as String,
        businessId: map['business_id'] as String,
        partyUuid: map['party_uuid'] as String,
        amountMinorUnits: map['amount_minor_units'] as int,
        isActive: (map['is_active'] as int) == 1,
        startDate: DateTime.parse(map['start_date'] as String),
      );
}

/// One paid period for a [SalaryRecord] — unique on `(salary_record_uuid,
/// period)` to prevent double-paying the same person for the same month,
/// same pattern as `DepreciationEntry`.
class SalaryPayment {
  SalaryPayment({
    required this.uuid,
    required this.salaryRecordUuid,
    required this.businessId,
    required this.period,
    required this.amountMinorUnits,
    required this.paidAt,
  });

  final String uuid;
  final String salaryRecordUuid;
  final String businessId;

  /// "YYYY-MM".
  final String period;
  final int amountMinorUnits;
  final DateTime paidAt;

  static const tableName = 'salary_payments';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      uuid TEXT PRIMARY KEY,
      salary_record_uuid TEXT NOT NULL,
      business_id TEXT NOT NULL,
      period TEXT NOT NULL,
      amount_minor_units INTEGER NOT NULL,
      paid_at TEXT NOT NULL,
      UNIQUE (salary_record_uuid, period)
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_salary_payments_record ON $tableName (salary_record_uuid)';

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'salary_record_uuid': salaryRecordUuid,
        'business_id': businessId,
        'period': period,
        'amount_minor_units': amountMinorUnits,
        'paid_at': paidAt.toIso8601String(),
      };

  factory SalaryPayment.fromMap(Map<String, Object?> map) => SalaryPayment(
        uuid: map['uuid'] as String,
        salaryRecordUuid: map['salary_record_uuid'] as String,
        businessId: map['business_id'] as String,
        period: map['period'] as String,
        amountMinorUnits: map['amount_minor_units'] as int,
        paidAt: DateTime.parse(map['paid_at'] as String),
      );
}
