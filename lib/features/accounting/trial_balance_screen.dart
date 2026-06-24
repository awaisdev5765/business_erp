import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

/// Trial Balance: every account's Dr/Cr totals and net balance — the
/// fundamental "do the books balance" check. Backed by
/// LedgerRepository.trialBalance(), a single grouped SQL query.
class TrialBalanceScreen extends ConsumerStatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  ConsumerState<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends ConsumerState<TrialBalanceScreen> {
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
        appBar: AppBar(title: const Text('Trial Balance')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    var totalDebit = 0;
    var totalCredit = 0;
    for (final row in rows) {
      totalDebit += row['total_debit'] as int;
      totalCredit += row['total_credit'] as int;
    }
    final balanced = totalDebit == totalCredit;
    final visibleRows = rows.where((r) => (r['total_debit'] as int) != 0 || (r['total_credit'] as int) != 0).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Trial Balance')),
      body: Column(
        children: [
          Expanded(
            child: visibleRows.isEmpty
                ? const Center(child: Text('No posted activity yet'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Account')),
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Debit'), numeric: true),
                        DataColumn(label: Text('Credit'), numeric: true),
                        DataColumn(label: Text('Balance'), numeric: true),
                      ],
                      rows: visibleRows.map((row) {
                        final debit = row['total_debit'] as int;
                        final credit = row['total_credit'] as int;
                        final balance = debit - credit;
                        return DataRow(cells: [
                          DataCell(Text('${row['code']}  ${row['name']}')),
                          DataCell(Text((row['type'] as String).toUpperCase())),
                          DataCell(Text(debit == 0 ? '—' : _money(debit))),
                          DataCell(Text(credit == 0 ? '—' : _money(credit))),
                          DataCell(Text(
                            balance >= 0 ? 'Dr ${_money(balance)}' : 'Cr ${_money(-balance)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: balance >= 0 ? AppColors.destructive : AppColors.success,
                            ),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Debit: ${_money(totalDebit)}', style: Theme.of(context).textTheme.titleMedium),
                Text('Total Credit: ${_money(totalCredit)}', style: Theme.of(context).textTheme.titleMedium),
                Chip(
                  avatar: Icon(
                    balanced ? Icons.check_circle : Icons.error,
                    size: 18,
                    color: balanced ? AppColors.success : AppColors.destructive,
                  ),
                  label: Text(balanced ? 'Balanced' : 'Out of balance'),
                  backgroundColor: (balanced ? AppColors.success : AppColors.destructive).withValues(alpha: 0.1),
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
