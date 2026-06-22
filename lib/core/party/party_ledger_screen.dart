import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../system/providers.dart';
import '../transaction/payment.dart';
import 'party.dart';

/// Statement of Account — every JournalLine touching this party,
/// chronological. This is "the Customer/Supplier Ledger" view described
/// in PHASES.md Section 11: a filtered read over `journal_lines`, not a
/// separate ledger table.
class PartyLedgerScreen extends ConsumerStatefulWidget {
  const PartyLedgerScreen({super.key, required this.party});

  final Party party;

  @override
  ConsumerState<PartyLedgerScreen> createState() => _PartyLedgerScreenState();
}

class _PartyLedgerScreenState extends ConsumerState<PartyLedgerScreen> {
  List<Map<String, Object?>>? _statement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(partyRepositoryProvider.future);
    final statement = await repo.statementOfAccount(widget.party.uuid);
    if (mounted) setState(() => _statement = statement);
  }

  Future<void> _showRecordPaymentDialog() async {
    final amountController = TextEditingController();
    final isCustomer = widget.party.type == PartyType.customer;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isCustomer ? 'Receive Payment' : 'Pay Supplier'),
        content: TextField(
          controller: amountController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Amount'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    final amount = ((double.tryParse(amountController.text) ?? 0) * 100).round();
    if (amount <= 0) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(paymentRepositoryProvider.future);
    await repo.record(
      businessId: businessId,
      partyUuid: widget.party.uuid,
      direction: isCustomer ? PaymentDirection.receiveFromCustomer : PaymentDirection.payToSupplier,
      amountMinorUnits: amount,
      createdBy: currentUser,
      deviceId: currentDeviceId,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    var runningBalance = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.payments),
            tooltip: 'Record Payment',
            onPressed: _showRecordPaymentDialog,
          ),
        ],
      ),
      body: statement == null
          ? const Center(child: CircularProgressIndicator())
          : statement.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : ListView.builder(
                  itemCount: statement.length,
                  itemBuilder: (context, index) {
                    final row = statement[index];
                    final debit = row['debit_minor_units'] as int;
                    final credit = row['credit_minor_units'] as int;
                    runningBalance += debit - credit;
                    final date = DateTime.parse(row['date'] as String);

                    return ListTile(
                      title: Text('${row['source_type']} — ${row['description'] ?? row['source_id']}'),
                      subtitle: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  •  ${row['status']}'),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (debit > 0) Text('Dr ${_money(debit)}', style: const TextStyle(color: Colors.red)),
                          if (credit > 0) Text('Cr ${_money(credit)}', style: const TextStyle(color: Colors.green)),
                          Text('Bal: ${_money(runningBalance)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
