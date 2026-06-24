import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/account.dart';
import '../../core/system/providers.dart';
import '../../shared/pdf/report_pdf.dart';
import '../../shared/theme/app_theme.dart';

/// Income accounts minus Expense accounts, optionally restricted to a
/// date range (LedgerRepository.trialBalanceForRange) — defaults to
/// all-time, same as before, when no range is set.
class ProfitAndLossScreen extends ConsumerStatefulWidget {
  const ProfitAndLossScreen({super.key});

  @override
  ConsumerState<ProfitAndLossScreen> createState() => _ProfitAndLossScreenState();
}

class _ProfitAndLossScreenState extends ConsumerState<ProfitAndLossScreen> {
  List<Map<String, Object?>>? _rows;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final rows = (_from == null && _to == null)
        ? await ledger.trialBalance(businessId: businessId)
        : await ledger.trialBalanceForRange(businessId: businessId, from: _from, to: _to);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  void _clearRange() {
    setState(() {
      _from = null;
      _to = null;
    });
    _load();
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
    final incomeLines = incomeRows.where((r) => earned(r) != 0).map((r) => ('${r['name']}', earned(r))).toList();
    final expenseLines = expenseRows.where((r) => spent(r) != 0).map((r) => ('${r['name']}', spent(r))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit & Loss'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Export PDF',
            onPressed: () async {
              final business = await ref.read(currentBusinessProvider.future);
              await ReportPdf.printProfitAndLoss(
                businessName: business.name,
                incomeRows: incomeLines,
                totalIncome: totalIncome,
                expenseRows: expenseLines,
                totalExpense: totalExpense,
                from: _from,
                to: _to,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_from == null ? 'From: any' : 'From: ${_formatDate(_from!)}'),
                onPressed: () => _pickDate(isFrom: true),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_to == null ? 'To: any' : 'To: ${_formatDate(_to!)}'),
                onPressed: () => _pickDate(isFrom: false),
              ),
              if (_from != null || _to != null)
                TextButton(onPressed: _clearRange, child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
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
            rows: incomeLines,
          ),
          const SizedBox(height: AppSpacing.xl),
          _Section(
            title: 'Expenses',
            total: totalExpense,
            color: AppColors.destructive,
            rows: expenseLines,
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

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
