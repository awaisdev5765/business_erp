enum SyncOperation { create, update, delete }

enum SyncQueueStatus { pending, syncing, synced, failed, conflict }

/// The local outbound queue ("outbox") — every record that needs to reach
/// Firestore gets one row here. This is scaffolding for Phase 5's sync
/// engine: with no live Firebase project yet (see PHASES.md), nothing
/// actually drains this queue — a background worker calling a Cloud
/// Function is the next piece, once a project exists. Until then this
/// table just accumulates, which is itself useful: `pendingCount()` is
/// exactly the "how much hasn't synced yet" the Sync Status screen shows.
///
/// Deliberately generic (entityType/entityId, not a typed payload column)
/// so every repository can enqueue through the same table without a
/// schema change per entity — see SyncQueueRepository.enqueue().
class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.businessId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    this.status = SyncQueueStatus.pending,
    this.attempts = 0,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String businessId;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final SyncQueueStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const tableName = 'sync_queue_items';

  static const createTableSql = '''
    CREATE TABLE $tableName (
      id TEXT PRIMARY KEY,
      business_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const createIndexSql =
      'CREATE INDEX idx_sync_queue_items_status ON $tableName (business_id, status)';

  Map<String, Object?> toMap() => {
        'id': id,
        'business_id': businessId,
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': operation.name,
        'status': status.name,
        'attempts': attempts,
        'last_error': lastError,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory SyncQueueItem.fromMap(Map<String, Object?> map) => SyncQueueItem(
        id: map['id'] as String,
        businessId: map['business_id'] as String,
        entityType: map['entity_type'] as String,
        entityId: map['entity_id'] as String,
        operation: SyncOperation.values.byName(map['operation'] as String),
        status: SyncQueueStatus.values.byName(map['status'] as String),
        attempts: map['attempts'] as int,
        lastError: map['last_error'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
