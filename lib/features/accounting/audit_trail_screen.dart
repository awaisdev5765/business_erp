import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/audit_log.dart';
import '../../core/system/providers.dart';

/// Read-only view of every Void/Reversal action — see PHASES.md Section
/// 16 ("Audit Trail") and AuditLogRepository for what gets logged here.
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
              ? const Center(child: Text('No void or reversal actions yet'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return ListTile(
                      leading: Icon(
                        log.action == 'void' ? Icons.block : Icons.undo,
                        color: log.action == 'void' ? Colors.red : Colors.orange,
                      ),
                      title: Text('${log.action.toUpperCase()} ${log.entityType} ${log.entityId.substring(0, 8)}'),
                      subtitle: Text('${log.details ?? ''}\nBy ${log.performedBy} at ${_formatDateTime(log.performedAt)}'),
                      isThreeLine: true,
                    );
                  },
                ),
    );
  }
}

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
