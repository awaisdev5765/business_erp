import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/conflict_record.dart';
import '../../core/sync/sync_queue_item.dart';
import '../../core/system/providers.dart';

/// Shows what's waiting to sync and any conflicts needing a decision,
/// plus a manual "Sync Now" trigger (`FirestoreSyncService.uploadPending`).
/// There's no automatic background worker yet — every posted JournalEntry
/// queues here and waits for either a manual sync or (future work) a
/// periodic/foreground-triggered upload. Download/merge from other
/// devices isn't wired in yet either — see PHASES.md Phase 5.
class SyncStatusScreen extends ConsumerStatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  ConsumerState<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends ConsumerState<SyncStatusScreen> {
  List<SyncQueueItem>? _items;
  List<ConflictRecord>? _conflicts;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final syncQueue = await ref.read(syncQueueRepositoryProvider.future);
    final conflicts = await ref.read(conflictRecordRepositoryProvider.future);

    final items = await syncQueue.all(businessId: businessId);
    final unresolved = await conflicts.unresolved(businessId: businessId);

    if (mounted) {
      setState(() {
        _items = items;
        _conflicts = unresolved;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final businessId = await ref.read(currentBusinessIdProvider.future);
      final service = await ref.read(firestoreSyncServiceProvider.future);
      final count = await service.uploadPending(businessId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Synced $count item(s)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final conflicts = _conflicts;

    if (items == null || conflicts == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pending = items.where((i) => i.status == SyncQueueStatus.pending).length;
    final failed = items.where((i) => i.status == SyncQueueStatus.failed).length;
    final synced = items.where((i) => i.status == SyncQueueStatus.synced).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _syncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  )
                : IconButton(icon: const Icon(Icons.sync), tooltip: 'Sync Now', onPressed: _syncNow),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatChip(label: 'Pending', count: pending, color: Colors.orange),
                _StatChip(label: 'Failed', count: failed, color: Colors.red),
                _StatChip(label: 'Synced', count: synced, color: Colors.green),
                _StatChip(label: 'Conflicts', count: conflicts.length, color: Colors.purple),
              ],
            ),
            const SizedBox(height: 24),
            if (conflicts.isNotEmpty) ...[
              Text('Needs Your Decision', style: Theme.of(context).textTheme.titleMedium),
              ...conflicts.map((c) => ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.purple),
                    title: Text('${c.entityType} ${c.entityId.substring(0, 8)}'),
                    subtitle: Text('Conflicting fields: ${c.conflictingFields.join(', ')}'),
                  )),
              const Divider(),
            ],
            Text('Queue', style: Theme.of(context).textTheme.titleMedium),
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Nothing queued yet.'))
            else
              ...items.map((item) => ListTile(
                    leading: Icon(_statusIcon(item.status), color: _statusColor(item.status)),
                    title: Text('${item.operation.name} ${item.entityType} ${item.entityId.substring(0, 8)}'),
                    subtitle: item.lastError != null ? Text(item.lastError!) : null,
                    trailing: item.attempts > 0 ? Text('${item.attempts} attempt(s)') : null,
                  )),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12))),
      label: Text(label),
    );
  }
}

IconData _statusIcon(SyncQueueStatus status) {
  switch (status) {
    case SyncQueueStatus.pending:
      return Icons.schedule;
    case SyncQueueStatus.syncing:
      return Icons.sync;
    case SyncQueueStatus.synced:
      return Icons.check_circle;
    case SyncQueueStatus.failed:
      return Icons.error_outline;
    case SyncQueueStatus.conflict:
      return Icons.warning_amber;
  }
}

Color _statusColor(SyncQueueStatus status) {
  switch (status) {
    case SyncQueueStatus.pending:
      return Colors.orange;
    case SyncQueueStatus.syncing:
      return Colors.blue;
    case SyncQueueStatus.synced:
      return Colors.green;
    case SyncQueueStatus.failed:
      return Colors.red;
    case SyncQueueStatus.conflict:
      return Colors.purple;
  }
}
