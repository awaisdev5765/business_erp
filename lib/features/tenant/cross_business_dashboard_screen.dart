import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../core/tenant/business.dart';

/// Read-only rollup across every business the signed-in user has Super
/// Admin access to — cash position and revenue, side by side. Never
/// commingles each business's actual ledgers; this is purely
/// informational, computed by querying each business's own
/// LedgerRepository in turn. See PHASES.md Phase 6 and the original
/// brief's "Business Health Comparison" dashboard concept.
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

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider);
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
          return _buildBody(rows);
        },
      ),
    );
  }

  Widget _buildBody(List<(Business, int, int)>? rows) {
    return rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Informational only — each business\'s books stay separate; '
                    'nothing here is a combined ledger.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  ...rows.map((row) {
                    final (business, cash, revenue) = row;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(business.name, style: Theme.of(context).textTheme.titleMedium),
                                  Text(business.type.name),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Cash: ${_money(cash)}'),
                                Text('Revenue: ${_money(revenue)}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
