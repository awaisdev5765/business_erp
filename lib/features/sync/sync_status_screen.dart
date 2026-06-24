import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/conflict_record.dart';
import '../../core/sync/sync_queue_item.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

/// Shows what's waiting to sync and any conflicts needing a decision,
/// plus a manual "Sync Now" trigger (`FirestoreSyncService.syncAll` —
/// upload then download). A periodic background trigger also runs from
/// `AppShell` while the app is open; this button is for an immediate,
/// user-visible sync rather than waiting for the next tick.
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
      final result = await service.syncAll(businessId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Pulled ${result.inserted} new, ${result.statusUpdated} updated'
            '${result.conflicts > 0 ? ', ${result.conflicts} conflict(s)' : ''}',
          ),
        ));
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
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _syncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(icon: const Icon(Icons.sync), tooltip: 'Sync Now', onPressed: _syncNow),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 700 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 2.2,
                  children: [
                    _StatCard(label: 'Pending', count: pending, icon: Icons.schedule, color: AppColors.warning),
                    _StatCard(label: 'Failed', count: failed, icon: Icons.error_outline, color: AppColors.destructive),
                    _StatCard(label: 'Synced', count: synced, icon: Icons.check_circle_outline, color: AppColors.success),
                    _StatCard(label: 'Conflicts', count: conflicts.length, icon: Icons.warning_amber, color: AppColors.accent),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            if (conflicts.isNotEmpty) ...[
              Text('Needs Your Decision', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              ...conflicts.map((c) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                      leading: const Icon(Icons.warning_amber, color: AppColors.accent),
                      title: Text('${c.entityType} ${c.entityId.substring(0, 8)}'),
                      subtitle: Text('Conflicting fields: ${c.conflictingFields.join(', ')}'),
                    ),
                  )),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('Queue', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text('Nothing queued yet.', style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              ...items.map((item) => Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                      leading: Icon(_statusIcon(item.status), color: _statusColor(item.status)),
                      title: Text('${item.operation.name} ${item.entityType} ${item.entityId.substring(0, 8)}'),
                      subtitle: item.lastError != null ? Text(item.lastError!) : null,
                      trailing: item.attempts > 0 ? Text('${item.attempts} attempt(s)') : null,
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.count, required this.icon, required this.color});

  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  Text('$count', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
            ),
          ],
        ),
      ),
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
      return AppColors.warning;
    case SyncQueueStatus.syncing:
      return AppColors.accent;
    case SyncQueueStatus.synced:
      return AppColors.success;
    case SyncQueueStatus.failed:
      return AppColors.destructive;
    case SyncQueueStatus.conflict:
      return AppColors.accent;
  }
}
