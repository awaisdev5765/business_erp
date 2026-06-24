import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../core/tenant/business.dart';
import '../../shared/theme/app_theme.dart';

/// A rollup across every business the signed-in Super Admin has access
/// to — cash position and revenue, side by side, computed by querying
/// each business's own LedgerRepository in turn (never commingling
/// their actual ledgers). See PHASES.md Phase 6 and the original
/// brief's "Business Health Comparison" dashboard concept. Tapping a
/// row switches the whole app over to that business — same action as
/// BusinessSwitcherScreen, just reachable from this list too.
class CrossBusinessDashboardScreen extends ConsumerStatefulWidget {
  const CrossBusinessDashboardScreen({super.key});

  @override
  ConsumerState<CrossBusinessDashboardScreen> createState() => _CrossBusinessDashboardScreenState();
}

class _CrossBusinessDashboardScreenState extends ConsumerState<CrossBusinessDashboardScreen> {
  List<(Business, int, int)>? _rows; // (business, cash, revenue)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessRepo = await ref.read(businessRepositoryProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);

    final businesses = await businessRepo.list();
    final rows = <(Business, int, int)>[];
    for (final business in businesses) {
      final cash = await ledger.accountBalanceMinorUnits(businessId: business.uuid, accountCode: '1010');
      final trialBalance = await ledger.trialBalance(businessId: business.uuid);
      final revenue = trialBalance
          .where((r) => (r['code'] as String).startsWith('4'))
          .fold<int>(0, (sum, r) => sum + ((r['total_credit'] as int) - (r['total_debit'] as int)));
      rows.add((business, cash, revenue));
    }

    if (mounted) setState(() => _rows = rows);
  }

  void _switchTo(Business business) {
    ref.read(selectedBusinessIdProvider.notifier).state = business.uuid;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Switched to ${business.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider);
    final activeId = ref.watch(currentBusinessIdProvider).valueOrNull;
    final rows = _rows;

    return Scaffold(
      appBar: AppBar(title: const Text('All Businesses')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('$e')),
        data: (profile) {
          if (profile == null || !profile.isSuperAdmin) {
            return const Center(child: Text('Super Admin access required.'));
          }
          return _buildBody(rows, activeId);
        },
      ),
    );
  }

  Widget _buildBody(List<(Business, int, int)>? rows, String? activeId) {
    if (rows == null) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text(
            'Tap a business to switch the whole app over to it. Each business\'s '
            'books stay separate — nothing here is a combined ledger.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...rows.map((row) {
            final (business, cash, revenue) = row;
            final isActive = business.uuid == activeId;
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: isActive ? null : () => _switchTo(business),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_iconFor(business.type), color: AppColors.accent, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(business.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (isActive) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Chip(
                                    label: const Text('Active'),
                                    backgroundColor: AppColors.success.withValues(alpha: 0.1),
                                    labelStyle: const TextStyle(color: AppColors.success, fontSize: 11),
                                    side: BorderSide.none,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ],
                            ),
                            Text(_labelFor(business.type), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Cash: ${_money(cash)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Revenue: ${_money(revenue)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                      if (!isActive) ...[
                        const SizedBox(width: AppSpacing.md),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

IconData _iconFor(BusinessType type) {
  switch (type) {
    case BusinessType.sparePartsShop:
      return Icons.store_outlined;
    case BusinessType.fishery:
      return Icons.directions_boat_outlined;
    case BusinessType.transport:
      return Icons.local_shipping_outlined;
  }
}

String _labelFor(BusinessType type) {
  switch (type) {
    case BusinessType.sparePartsShop:
      return 'Spare Parts Shop';
    case BusinessType.fishery:
      return 'Fishery';
    case BusinessType.transport:
      return 'Transport';
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
