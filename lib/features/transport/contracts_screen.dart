import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import 'contract.dart';

class ContractsScreen extends ConsumerStatefulWidget {
  const ContractsScreen({super.key});

  @override
  ConsumerState<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends ConsumerState<ContractsScreen> {
  List<Contract>? _contracts;
  Map<String, Party> _customersByUuid = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final contractRepo = await ref.read(contractRepositoryProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);

    final contracts = await contractRepo.list(businessId: businessId);
    final customers = await partyRepo.list(businessId: businessId, type: PartyType.customer);

    if (mounted) {
      setState(() {
        _contracts = contracts;
        _customersByUuid = {for (final c in customers) c.uuid: c};
      });
    }
  }

  Future<void> _showAddDialog() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);
    final customers = await partyRepo.list(businessId: businessId, type: PartyType.customer);

    if (customers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a customer/company first')));
      }
      return;
    }

    Party selectedCustomer = customers.first;
    final descController = TextEditingController();
    final rateController = TextEditingController();

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Contract'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Party>(
                initialValue: selectedCustomer,
                decoration: const InputDecoration(labelText: 'Company'),
                items: customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (v) => setDialogState(() => selectedCustomer = v ?? customers.first),
              ),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
              TextField(
                controller: rateController,
                decoration: const InputDecoration(labelText: 'Rate per trip (optional)'),
                keyboardType: TextInputType.number,
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

    final repo = await ref.read(contractRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      customerUuid: selectedCustomer.uuid,
      description: descController.text,
      ratePerTripMinorUnits: rateController.text.isEmpty ? null : ((double.tryParse(rateController.text) ?? 0) * 100).round(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final contracts = _contracts;
    return Scaffold(
      appBar: AppBar(title: const Text('Contracts')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: contracts == null
          ? const Center(child: CircularProgressIndicator())
          : contracts.isEmpty
              ? const Center(child: Text('No contracts yet — tap + to add one.'))
              : ListView.builder(
                  itemCount: contracts.length,
                  itemBuilder: (context, index) {
                    final contract = contracts[index];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(contract.description),
                      subtitle: Text(_customersByUuid[contract.customerUuid]?.name ?? contract.customerUuid),
                      trailing: contract.ratePerTripMinorUnits != null
                          ? Text(_money(contract.ratePerTripMinorUnits!))
                          : null,
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
