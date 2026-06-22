import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Trial Balance')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final debit = row['total_debit'] as int;
                final credit = row['total_credit'] as int;
                final balance = debit - credit;
                if (debit == 0 && credit == 0) return const SizedBox.shrink();
                return ListTile(
                  title: Text('${row['code']}  ${row['name']}'),
                  subtitle: Text((row['type'] as String).toUpperCase()),
                  trailing: Text(
                    balance >= 0 ? 'Dr ${_money(balance)}' : 'Cr ${_money(-balance)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: balance >= 0 ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Debit: ${_money(totalDebit)}', style: Theme.of(context).textTheme.titleMedium),
                Text('Total Credit: ${_money(totalCredit)}', style: Theme.of(context).textTheme.titleMedium),
                Icon(
                  totalDebit == totalCredit ? Icons.check_circle : Icons.error,
                  color: totalDebit == totalCredit ? Colors.green : Colors.red,
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
