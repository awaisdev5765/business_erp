/// Per-business, per-transaction-type approval gate: a credit Sale or
/// TripIncome above [thresholdMinorUnits] is held as `pendingApproval`
/// instead of posting immediately, until a Manager/Business Admin
/// approves it. Optional/opt-in, same pattern as FiscalPeriod — a
/// business with no threshold configured for a transaction type posts
/// freely, unchanged from every earlier phase. See PHASES.md Phase 6.
class ApprovalThreshold {
  ApprovalThreshold({
    required this.businessId,
    required this.transactionType,
    required this.thresholdMinorUnits,
  });

  final String businessId;

  /// e.g. "sale", "tripIncome".
  final String transactionType;
  final int thresholdMinorUnits;

  static const tableName = 'approval_thresholds';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      business_id TEXT NOT NULL,
      transaction_type TEXT NOT NULL,
      threshold_minor_units INTEGER NOT NULL,
      PRIMARY KEY (business_id, transaction_type)
    )
  ''';

  Map<String, Object?> toMap() => {
        'business_id': businessId,
        'transaction_type': transactionType,
        'threshold_minor_units': thresholdMinorUnits,
      };

  factory ApprovalThreshold.fromMap(Map<String, Object?> map) => ApprovalThreshold(
        businessId: map['business_id'] as String,
        transactionType: map['transaction_type'] as String,
        thresholdMinorUnits: map['threshold_minor_units'] as int,
      );
}
