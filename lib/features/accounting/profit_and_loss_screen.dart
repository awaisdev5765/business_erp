import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/account.dart';
import '../../core/system/providers.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Profit & Loss')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Income', style: Theme.of(context).textTheme.titleLarge),
          ...incomeRows.where((r) => earned(r) != 0).map(
                (r) => ListTile(title: Text('${r['name']}'), trailing: Text(_money(earned(r)))),
              ),
          const Divider(),
          ListTile(
            title: const Text('Total Income', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text(_money(totalIncome), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
          Text('Expenses', style: Theme.of(context).textTheme.titleLarge),
          ...expenseRows.where((r) => spent(r) != 0).map(
                (r) => ListTile(title: Text('${r['name']}'), trailing: Text(_money(spent(r)))),
              ),
          const Divider(),
          ListTile(
            title: const Text('Total Expenses', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text(_money(totalExpense), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
          Card(
            color: netProfit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
            child: ListTile(
              title: Text(
                netProfit >= 0 ? 'Net Profit' : 'Net Loss',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              trailing: Text(
                _money(netProfit.abs()),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: netProfit >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
