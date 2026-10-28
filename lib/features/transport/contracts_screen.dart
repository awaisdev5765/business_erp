import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';
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
          title: const Text('Company Rate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Party>(
                initialValue: selectedCustomer,
                decoration: const InputDecoration(labelText: 'Company'),
                items: customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (v) => setDialogState(() => selectedCustomer = v ?? customers.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: rateController,
                decoration: const InputDecoration(labelText: 'Rate per ton'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

    final repo = await ref.read(contractRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      customerUuid: selectedCustomer.uuid,
      description: descController.text.trim().isEmpty ? selectedCustomer.name : descController.text.trim(),
      ratePerTonMinorUnits: rateController.text.isEmpty ? null : ((double.tryParse(rateController.text) ?? 0) * 100).round(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final contracts = _contracts;
    return Scaffold(
      appBar: AppBar(title: const Text('Company Rates')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: contracts == null
          ? const Center(child: CircularProgressIndicator())
          : contracts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: AppSpacing.md),
                      const Text('No company rates yet — tap + (company + Rs per ton).'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: contracts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final contract = contracts[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.description_outlined, color: AppColors.accent, size: 18),
                        ),
                        title: Text(_customersByUuid[contract.customerUuid]?.name ?? contract.customerUuid),
                        subtitle: Text(contract.description),
                        trailing: contract.ratePerTonMinorUnits != null
                            ? Text('${_money(contract.ratePerTonMinorUnits!)} / ton', style: const TextStyle(fontWeight: FontWeight.w700))
                            : contract.ratePerTripMinorUnits != null
                                ? Text(_money(contract.ratePerTripMinorUnits!), style: const TextStyle(fontWeight: FontWeight.w700))
                                : null,
                      ),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
