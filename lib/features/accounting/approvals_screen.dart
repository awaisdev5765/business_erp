import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/read_only_banner.dart';
import '../spare_parts/sales/sale.dart';

/// Every credit Sale held `pendingApproval` because it exceeded the
/// business's configured threshold (PHASES.md Phase 6) — tap to approve,
/// which posts the JournalEntry and decrements stock for real. There's
/// no "reject" action yet; a sale that shouldn't have happened at all is
/// a Void on the resulting posted entry once approved, or — if it's
/// still pending — there's currently no way to cancel it outright
/// (deferred, same as how this app generally favors append-only
/// correction over deletion).
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  List<Sale>? _pending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(saleRepositoryProvider.future);
    final pending = await repo.pendingApproval(businessId: businessId);
    if (mounted) setState(() => _pending = pending);
  }

  Future<void> _approve(Sale sale) async {
    final repo = await ref.read(saleRepositoryProvider.future);
    try {
      await repo.approve(
        sale.uuid,
        approvedBy: currentUser,
        deviceId: currentDeviceId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approved ${sale.documentNumber}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final isReadOnly = ref.watch(isReadOnlyProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: Column(
        children: [
          if (isReadOnly) const ReadOnlyBanner(),
          Expanded(
            child: pending == null
                ? const Center(child: CircularProgressIndicator())
                : pending.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text('Nothing waiting on approval.'),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: pending.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final sale = pending[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.hourglass_top,
                              color: AppColors.warning,
                              size: 18,
                            ),
                          ),
                          title: Text('Sale ${sale.documentNumber}'),
                          subtitle: Text(
                            '${_money(sale.grandTotalMinorUnits)}  •  ${_formatDate(sale.date)}',
                          ),
                          trailing: FilledButton(
                            onPressed: isReadOnly ? null : () => _approve(sale),
                            child: const Text('Approve'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
