import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/audit_log.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

/// Read-only view of every logged action — originally just Void/Reversal
/// (PHASES.md Section 16), now also every Sale/Purchase/Product create
/// and Sale approval, so "who did what" is traceable for normal
/// activity too, not just corrections. See AuditLogRepository.
class AuditTrailScreen extends ConsumerStatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  ConsumerState<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends ConsumerState<AuditTrailScreen> {
  List<AuditLog>? _logs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(auditLogRepositoryProvider.future);
    final logs = await repo.list(businessId: businessId);
    if (mounted) setState(() => _logs = logs);
  }

  @override
  Widget build(BuildContext context) {
    final logs = _logs;
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail')),
      body: logs == null
          ? const Center(child: CircularProgressIndicator())
          : logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: AppSpacing.md),
                      const Text('No activity logged yet'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final color = _colorFor(log.action);
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Icon(_iconFor(log.action), color: color, size: 18),
                        ),
                        title: Text('${log.action.toUpperCase()} ${log.entityType} ${log.entityId.substring(0, 8)}'),
                        subtitle: Text('${log.details ?? ''}\nBy ${log.performedBy} at ${_formatDateTime(log.performedAt)}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}

IconData _iconFor(String action) {
  switch (action) {
    case 'void':
      return Icons.block;
    case 'reverse':
      return Icons.undo;
    case 'approve':
      return Icons.check_circle_outline;
    case 'create_pending_approval':
      return Icons.hourglass_top;
    default:
      return Icons.add_circle_outline; // create
  }
}

Color _colorFor(String action) {
  switch (action) {
    case 'void':
      return AppColors.destructive;
    case 'reverse':
      return AppColors.warning;
    case 'approve':
      return AppColors.success;
    case 'create_pending_approval':
      return AppColors.warning;
    default:
      return AppColors.accent; // create
  }
}

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
