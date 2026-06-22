import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../system/providers.dart';
import 'party.dart';
import 'party_ledger_screen.dart';

class PartyListScreen extends ConsumerStatefulWidget {
  const PartyListScreen({super.key, required this.type});

  final PartyType type;

  @override
  ConsumerState<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends ConsumerState<PartyListScreen> {
  List<(Party, int)>? _partiesWithBalance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    final parties = await repo.list(businessId: businessId, type: widget.type);
    final withBalance = <(Party, int)>[];
    for (final party in parties) {
      final balance = await repo.outstandingBalanceMinorUnits(party.uuid);
      withBalance.add((party, balance));
    }
    if (mounted) setState(() => _partiesWithBalance = withBalance);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.type == PartyType.customer ? 'New Customer' : 'New Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true || nameController.text.isEmpty) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      type: widget.type,
      name: nameController.text,
      phone: phoneController.text.isEmpty ? null : phoneController.text,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.type == PartyType.customer;
    final data = _partiesWithBalance;

    return Scaffold(
      appBar: AppBar(title: Text(isCustomer ? 'Customers' : 'Suppliers')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : data.isEmpty
              ? Center(child: Text('No ${isCustomer ? 'customers' : 'suppliers'} yet — tap + to add one.'))
              : ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final (party, balance) = data[index];
                    // Receivable (customer owes us) is positive Dr; payable
                    // (we owe supplier) is negative Cr — see PartyRepository.
                    final owesUs = isCustomer ? balance : -balance;
                    return ListTile(
                      title: Text(party.name),
                      subtitle: party.phone != null ? Text(party.phone!) : null,
                      trailing: Text(
                        _money(owesUs.abs()),
                        style: TextStyle(
                          color: owesUs > 0 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PartyLedgerScreen(party: party)),
                      ),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
