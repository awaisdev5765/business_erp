import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/bank_account.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';
import 'bank_reconciliation_screen.dart';

class BankAccountsScreen extends ConsumerStatefulWidget {
  const BankAccountsScreen({super.key});

  @override
  ConsumerState<BankAccountsScreen> createState() => _BankAccountsScreenState();
}

class _BankAccountsScreenState extends ConsumerState<BankAccountsScreen> {
  List<BankAccount>? _accounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(bankAccountRepositoryProvider.future);
    final accounts = await repo.list(businessId: businessId);
    if (mounted) setState(() => _accounts = accounts);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final bankController = TextEditingController();
    final numberController = TextEditingController();
    final openingController = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Bank Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Account name')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: bankController, decoration: const InputDecoration(labelText: 'Bank name')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: numberController, decoration: const InputDecoration(labelText: 'Account number')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: openingController,
              decoration: const InputDecoration(labelText: 'Opening balance'),
              keyboardType: TextInputType.number,
            ),
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
    final repo = await ref.read(bankAccountRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      name: nameController.text,
      bankName: bankController.text.isEmpty ? null : bankController.text,
      accountNumber: numberController.text.isEmpty ? null : numberController.text,
      openingBalanceMinorUnits: ((double.tryParse(openingController.text) ?? 0) * 100).round(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Bank Accounts')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: accounts == null
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: AppSpacing.md),
                      const Text('No bank accounts yet — tap + to add one.'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.account_balance_outlined, color: AppColors.accent, size: 18),
                        ),
                        title: Text(account.name),
                        subtitle: Text('${account.bankName ?? ''} ${account.accountNumber ?? ''}'.trim()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => BankReconciliationScreen(account: account)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
