import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/bank_account.dart';
import '../../core/system/providers.dart';

/// Basic reconciliation: enter the bank's statement lines, tick them off
/// as cleared, and compare the cleared running total against the
/// statement's stated closing balance. See BankAccount's doc comment for
/// what's deferred (CSV/OFX import, wiring Sales/Payments to a specific
/// bank account instead of generic Cash/Bank GL accounts).
class BankReconciliationScreen extends ConsumerStatefulWidget {
  const BankReconciliationScreen({super.key, required this.account});

  final BankAccount account;

  @override
  ConsumerState<BankReconciliationScreen> createState() => _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends ConsumerState<BankReconciliationScreen> {
  List<BankStatementLine>? _lines;
  int? _clearedBalance;
  final _statementBalanceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(bankAccountRepositoryProvider.future);
    final lines = await repo.statementLines(bankAccountUuid: widget.account.uuid);
    final balance = await repo.clearedBalanceMinorUnits(widget.account);
    if (mounted) {
      setState(() {
        _lines = lines;
        _clearedBalance = balance;
      });
    }
  }

  Future<void> _toggleCleared(BankStatementLine line) async {
    final repo = await ref.read(bankAccountRepositoryProvider.future);
    await repo.setCleared(line.uuid, !line.isCleared);
    await _load();
  }

  Future<void> _showAddLineDialog() async {
    final descController = TextEditingController();
    final amountController = TextEditingController();
    var isDeposit = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Statement Line'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Deposit')),
                  ButtonSegment(value: false, label: Text('Withdrawal')),
                ],
                selected: {isDeposit},
                onSelectionChanged: (s) => setDialogState(() => isDeposit = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true || descController.text.isEmpty) return;
    final amount = ((double.tryParse(amountController.text) ?? 0) * 100).round();
    if (amount <= 0) return;

    final repo = await ref.read(bankAccountRepositoryProvider.future);
    await repo.addStatementLine(
      bankAccountUuid: widget.account.uuid,
      date: DateTime.now(),
      description: descController.text,
      amountMinorUnits: isDeposit ? amount : -amount,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final clearedBalance = _clearedBalance;
    final statementBalance = (double.tryParse(_statementBalanceController.text) ?? 0) * 100;
    final difference = clearedBalance == null ? null : clearedBalance - statementBalance.round();

    return Scaffold(
      appBar: AppBar(title: Text(widget.account.name)),
      floatingActionButton: FloatingActionButton(onPressed: _showAddLineDialog, child: const Icon(Icons.add)),
      body: lines == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _statementBalanceController,
                          decoration: const InputDecoration(
                            labelText: 'Statement closing balance',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Cleared balance: ${_money(clearedBalance ?? 0)}'),
                          if (difference != null)
                            Text(
                              difference == 0 ? 'Reconciled ✓' : 'Difference: ${_money(difference)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: difference == 0 ? Colors.green : Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: lines.isEmpty
                      ? const Center(child: Text('No statement lines yet — tap + to add one.'))
                      : ListView.builder(
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            return CheckboxListTile(
                              value: line.isCleared,
                              onChanged: (_) => _toggleCleared(line),
                              title: Text(line.description),
                              subtitle: Text(_formatDate(line.date)),
                              secondary: Text(
                                _money(line.amountMinorUnits),
                                style: TextStyle(
                                  color: line.amountMinorUnits >= 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
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
