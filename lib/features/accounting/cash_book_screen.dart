import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

/// Cash Book: every JournalLine posted to the Cash on Hand account
/// (1010), chronological with a running balance — same pattern as the
/// Customer/Supplier Ledger, just filtered by account instead of party.
/// See PHASES.md Section 11.
class CashBookScreen extends ConsumerStatefulWidget {
  const CashBookScreen({super.key});

  @override
  ConsumerState<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends ConsumerState<CashBookScreen> {
  static const _cashAccountCode = '1010';
  List<Map<String, Object?>>? _statement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final statement = await ledger.accountStatement(businessId: businessId, accountCode: _cashAccountCode);
    if (mounted) setState(() => _statement = statement);
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    final currentBalance =
        statement?.fold<int>(0, (sum, row) => sum + (row['debit_minor_units'] as int) - (row['credit_minor_units'] as int));

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Book')),
      body: statement == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Card(
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
                            child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.accent, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Text('Current Balance', style: TextStyle(color: Colors.grey.shade600)),
                          const Spacer(),
                          Text(
                            _money(currentBalance ?? 0),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: statement.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: AppSpacing.md),
                              const Text('No cash transactions yet'),
                            ],
                          ),
                        )
                      : _buildList(statement),
                ),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, Object?>> statement) {
    var runningBalance = 0;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      itemCount: statement.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final row = statement[index];
        final debit = row['debit_minor_units'] as int;
        final credit = row['credit_minor_units'] as int;
        runningBalance += debit - credit;
        final isIn = debit > 0;
        final date = DateTime.parse(row['date'] as String);

        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isIn ? AppColors.success : AppColors.destructive).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIn ? Icons.south_west : Icons.north_east,
                size: 16,
                color: isIn ? AppColors.success : AppColors.destructive,
              ),
            ),
            title: Text('${row['source_type']} — ${row['description'] ?? row['source_id']}'),
            subtitle: Text(
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  •  ${row['status']}',
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${isIn ? '+' : '-'}${_money(isIn ? debit : credit)}',
                  style: TextStyle(color: isIn ? AppColors.success : AppColors.destructive, fontWeight: FontWeight.w700),
                ),
                Text('Bal: ${_money(runningBalance)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
