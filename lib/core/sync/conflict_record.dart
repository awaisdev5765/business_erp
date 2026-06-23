enum ConflictRecordStatus { unresolved, resolvedLocal, resolvedRemote }

/// Persists a conflict that [ConflictResolutionPolicy] decided needs a
/// human decision — the data behind the "Manual Conflict Resolution UI"
/// from PHASES.md Section 15. Nothing populates this table yet without a
/// live sync engine talking to a real Firestore project; it exists now so
/// the resolution UI and workflow can be built and tested ahead of that.
class ConflictRecord {
  ConflictRecord({
    required this.id,
    required this.businessId,
    required this.entityType,
    required this.entityId,
    required this.conflictingFields,
    this.status = ConflictRecordStatus.unresolved,
    required this.detectedAt,
  });

  final String id;
  final String businessId;
  final String entityType;
  final String entityId;

  /// Comma-separated field names — kept simple (no JSON column) since
  /// this is scaffolding pending real usage patterns from an actual
  /// sync engine.
  final List<String> conflictingFields;
  final ConflictRecordStatus status;
  final DateTime detectedAt;

  static const tableName = 'conflict_records';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      conflicting_fields TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'unresolved',
      detected_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_conflict_records_business ON $tableName (business_id, status)';

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'entity_type': entityType,
        'entity_id': entityId,
        'conflicting_fields': conflictingFields.join(','),
        'status': status.name,
        'detected_at': detectedAt.toIso8601String(),
      };

  factory ConflictRecord.fromMap(Map<String, Object?> map) => ConflictRecord(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        entityType: map['entity_type'] as String,
        entityId: map['entity_id'] as String,
        conflictingFields: (map['conflicting_fields'] as String).split(',').where((s) => s.isNotEmpty).toList(),
        status: ConflictRecordStatus.values.byName(map['status'] as String),
        detectedAt: DateTime.parse(map['detected_at'] as String),
      );
}
