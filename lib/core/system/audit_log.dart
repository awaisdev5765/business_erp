/// Append-only record of sensitive actions — currently Void and Reversal,
/// the two actions PHASES.md Section 16/2 calls out as needing a visible
/// audit trail. Not every CRUD action is logged here (that would just
/// duplicate StockMovement/JournalEntry's own history) — this table is
/// specifically for actions that change *what a past record means*.
class AuditLog {
  AuditLog({
    required this.id,
    required this.businessId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.performedBy,
    required this.performedAt,
    this.details,
  });

  final String id;
  final String businessId;

  /// e.g. "void", "reverse".
  final String action;

  /// e.g. "JournalEntry".
  final String entityType;
  final String entityId;
  final String performedBy;
  final DateTime performedAt;
  final String? details;

  static const tableName = 'audit_logs';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      action TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      performed_by TEXT NOT NULL,
      performed_at TEXT NOT NULL,
      details TEXT
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_audit_logs_business ON $tableName (business_id, performed_at)';

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'performed_by': performedBy,
        'performed_at': performedAt.toIso8601String(),
        'details': details,
      };

  factory AuditLog.fromMap(Map<String, Object?> map) => AuditLog(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        action: map['action'] as String,
        entityType: map['entity_type'] as String,
        entityId: map['entity_id'] as String,
        performedBy: map['performed_by'] as String,
        performedAt: DateTime.parse(map['performed_at'] as String),
        details: map['details'] as String?,
      );
}
