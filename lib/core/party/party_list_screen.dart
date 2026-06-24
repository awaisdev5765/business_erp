import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../system/providers.dart';
import '../../shared/currency/currency.dart';
import '../../shared/theme/app_theme.dart';
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
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        title: Text(
          widget.type == PartyType.customer ? 'New Customer' : 'New Supplier',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
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
    final currency = ref.watch(currentCurrencyProvider).value;
    final filtered = data == null
        ? null
        : (_query.isEmpty
              ? data
              : data
                    .where((d) => d.$1.name.toLowerCase().contains(_query))
                    .toList());

    return Scaffold(
      appBar: AppBar(title: Text(isCustomer ? 'Customers' : 'Suppliers')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (data.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search ${isCustomer ? 'customers' : 'suppliers'}...',
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                Expanded(
                  child: data.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCustomer
                                    ? Icons.people_outline
                                    : Icons.local_shipping_outlined,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                'No ${isCustomer ? 'customers' : 'suppliers'} yet — tap + to add one.',
                              ),
                            ],
                          ),
                        )
                      : filtered!.isEmpty
                      ? Center(
                          child: Text(
                            'No matches for "$_query"',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final (party, balance) = filtered[index];
                            // Receivable (customer owes us) is positive Dr; payable
                            // (we owe supplier) is negative Cr — see PartyRepository.
                            final owesUs = isCustomer ? balance : -balance;
                            final initials = party.name.trim().isEmpty
                                ? '?'
                                : party.name
                                      .trim()
                                      .split(RegExp(r'\s+'))
                                      .take(2)
                                      .map((w) => w[0].toUpperCase())
                                      .join();

                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                  vertical: AppSpacing.xs,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.accent.withValues(
                                    alpha: 0.12,
                                  ),
                                  foregroundColor: AppColors.accent,
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                title: Text(party.name),
                                subtitle: party.phone != null
                                    ? Text(party.phone!)
                                    : null,
                                trailing: owesUs == 0
                                    ? Text(
                                        'Settled',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            owesUs > 0
                                                ? Icons.arrow_upward
                                                : Icons.arrow_downward,
                                            size: 14,
                                            color: owesUs > 0
                                                ? AppColors.destructive
                                                : AppColors.success,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            formatMoney(owesUs.abs(), currency),
                                            style: TextStyle(
                                              color: owesUs > 0
                                                  ? AppColors.destructive
                                                  : AppColors.success,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PartyLedgerScreen(party: party),
                                  ),
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
