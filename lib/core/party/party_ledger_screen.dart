import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/currency/currency.dart';
import '../../shared/theme/app_theme.dart';
import '../accounting/journal_entry.dart';
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
    final noteController = TextEditingController();
    final isCustomer = widget.party.type == PartyType.customer;
    var method = PaymentSettlementMethod.cash;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isCustomer ? 'Receive Payment' : 'Pay Supplier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<PaymentSettlementMethod>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: PaymentSettlementMethod.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(_methodLabel(m))))
                    .toList(),
                onChanged: (v) => setDialogState(() => method = v ?? PaymentSettlementMethod.cash),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Reference / note (optional)'),
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
      method: method,
      note: noteController.text.isEmpty ? null : noteController.text,
      createdBy: currentUser,
      deviceId: currentDeviceId,
    );
    await _load();
  }

  Future<void> _showVoidDialog(String entryUuid) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voiding removes this transaction from all balances permanently. '
              'The record itself is kept for audit purposes, but it stops counting '
              'anywhere. Use this only if the transaction should never have been '
              'recorded at all — for a transaction that happened but needs '
              'correcting, use a reversal instead.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reasonController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (reasonController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A reason is required')));
      }
      return;
    }

    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final entry = await ledger.findByUuid(entryUuid);
    if (entry == null) return;

    try {
      await ledger.void_(entry, voidedBy: currentUser, reason: reasonController.text.trim());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    final currency = ref.watch(currentCurrencyProvider).value;
    var runningBalance = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            tooltip: 'Record Payment',
            onPressed: _showRecordPaymentDialog,
          ),
        ],
      ),
      body: statement == null
          ? const Center(child: CircularProgressIndicator())
          : statement.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: AppSpacing.md),
                      const Text('No transactions yet'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: statement.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final row = statement[index];
                    final debit = row['debit_minor_units'] as int;
                    final credit = row['credit_minor_units'] as int;
                    runningBalance += debit - credit;
                    final date = DateTime.parse(row['date'] as String);
                    final status = row['status'] as String;
                    final entryUuid = row['entry_uuid'] as String;
                    final isPayment = row['source_type'] == 'Payment';

                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (isPayment ? AppColors.success : AppColors.accent).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isPayment ? Icons.payments_outlined : Icons.receipt_long_outlined,
                            color: isPayment ? AppColors.success : AppColors.accent,
                            size: 18,
                          ),
                        ),
                        title: Text('${row['source_type']} — ${row['description'] ?? row['source_id']}'),
                        subtitle: Text('${_formatDate(date)}  •  $status'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (debit > 0)
                                  Text(
                                    'Dr ${formatMoney(debit, currency)}',
                                    style: const TextStyle(color: AppColors.destructive, fontWeight: FontWeight.w600),
                                  ),
                                if (credit > 0)
                                  Text(
                                    'Cr ${formatMoney(credit, currency)}',
                                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
                                  ),
                                Text(
                                  'Bal: ${formatMoney(runningBalance, currency)}',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                            if (status == JournalEntryStatus.posted.name)
                              IconButton(
                                icon: const Icon(Icons.block, size: 18),
                                tooltip: 'Void this transaction',
                                onPressed: () => _showVoidDialog(entryUuid),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

String _methodLabel(PaymentSettlementMethod method) {
  switch (method) {
    case PaymentSettlementMethod.cash:
      return 'Cash';
    case PaymentSettlementMethod.bankTransfer:
      return 'Bank Transfer';
    case PaymentSettlementMethod.cheque:
      return 'Cheque';
    case PaymentSettlementMethod.card:
      return 'Card';
    case PaymentSettlementMethod.other:
      return 'Other';
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
    '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
