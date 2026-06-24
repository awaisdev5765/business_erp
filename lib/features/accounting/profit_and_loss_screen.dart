import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/account.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

/// Basic P&L: Income accounts minus Expense accounts, all-time (date-range
/// filtering is a later addition once Fiscal Periods land in Phase 2).
/// Reuses LedgerRepository.trialBalance() rather than a separate query —
/// P&L is just the trial balance's income/expense rows, re-signed to their
/// natural balance direction.
class ProfitAndLossScreen extends ConsumerStatefulWidget {
  const ProfitAndLossScreen({super.key});

  @override
  ConsumerState<ProfitAndLossScreen> createState() => _ProfitAndLossScreenState();
}

class _ProfitAndLossScreenState extends ConsumerState<ProfitAndLossScreen> {
  List<Map<String, Object?>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final rows = await ledger.trialBalance(businessId: businessId);
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profit & Loss')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final incomeRows = rows.where((r) => r['type'] == AccountType.income.name).toList();
    final expenseRows = rows.where((r) => r['type'] == AccountType.expense.name).toList();

    // Income accounts run Cr-normal: amount earned = credit - debit.
    int earned(Map<String, Object?> r) => (r['total_credit'] as int) - (r['total_debit'] as int);
    // Expense accounts run Dr-normal: amount spent = debit - credit.
    int spent(Map<String, Object?> r) => (r['total_debit'] as int) - (r['total_credit'] as int);

    final totalIncome = incomeRows.fold<int>(0, (sum, r) => sum + earned(r));
    final totalExpense = expenseRows.fold<int>(0, (sum, r) => sum + spent(r));
    final netProfit = totalIncome - totalExpense;
    final isProfit = netProfit >= 0;
    final color = isProfit ? AppColors.success : AppColors.destructive;

    return Scaffold(
      appBar: AppBar(title: const Text('Profit & Loss')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(isProfit ? Icons.trending_up : Icons.trending_down, color: color, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Text(isProfit ? 'Net Profit' : 'Net Loss', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    _money(netProfit.abs()),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _Section(
            title: 'Income',
            total: totalIncome,
            color: AppColors.success,
            rows: incomeRows.where((r) => earned(r) != 0).map((r) => ('${r['name']}', earned(r))).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
          _Section(
            title: 'Expenses',
            total: totalExpense,
            color: AppColors.destructive,
            rows: expenseRows.where((r) => spent(r) != 0).map((r) => ('${r['name']}', spent(r))).toList(),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.total, required this.color, required this.rows});

  final String title;
  final int total;
  final Color color;
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('No activity yet', style: TextStyle(color: Colors.grey.shade600)),
              ),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(r.$1), Text(_money(r.$2))],
                  ),
                )),
            const Divider(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total $title', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_money(total), style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
