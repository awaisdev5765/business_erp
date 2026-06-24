import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/account.dart';
import '../../core/accounting/expense.dart';
import '../../core/system/providers.dart';
import '../../shared/currency/currency.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/read_only_banner.dart';

/// Record a general business expense (rent, utilities, anything that
/// isn't a Purchase, Payroll, or trip cost) — previously there was no
/// way to post to an expense account at all outside those three flows.
/// Posts Dr {expense account} / Cr Cash-or-Bank via ExpenseRepository.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  List<Expense>? _expenses;
  List<Account> _expenseAccounts = [];
  Map<String, Account> _accountsByCode = {};
  String? _currency;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final db = await ref.read(databaseProvider.future);
    final repo = await ref.read(expenseRepositoryProvider.future);
    final business = await ref.read(currentBusinessProvider.future);

    final expenses = await repo.list(businessId: businessId);
    final accountRows = await db.query(
      Account.tableName,
      where: 'business_id = ? AND type = ? AND is_active = 1',
      whereArgs: [businessId, AccountType.expense.name],
      orderBy: 'code ASC',
    );
    final accounts = accountRows.map(Account.fromMap).toList();

    if (mounted) {
      setState(() {
        _expenses = expenses;
        _expenseAccounts = accounts;
        _accountsByCode = {for (final a in accounts) a.code: a};
        _currency = business.baseCurrency;
      });
    }
  }

  Future<void> _showAddDialog() async {
    if (_expenseAccounts.isEmpty) return;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    var accountCode = _expenseAccounts.first.code;
    var method = ExpensePaymentMethod.cash;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: accountCode,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _expenseAccounts.map((a) => DropdownMenuItem(value: a.code, child: Text(a.name))).toList(),
                  onChanged: (v) => setDialogState(() => accountCode = v ?? accountCode),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: amountController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ExpensePaymentMethod>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Paid via'),
                  items: ExpensePaymentMethod.values
                      .map((m) => DropdownMenuItem(value: m, child: Text(_methodLabel(m))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => method = v ?? ExpensePaymentMethod.cash),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                ),
              ],
            ),
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
    final repo = await ref.read(expenseRepositoryProvider.future);
    try {
      await repo.create(
        businessId: businessId,
        accountCode: accountCode,
        amountMinorUnits: amount,
        description: descriptionController.text.isEmpty ? null : descriptionController.text,
        method: method,
        createdBy: currentUser,
        deviceId: currentDeviceId,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenses = _expenses;
    final isReadOnly = ref.watch(isReadOnlyProvider).value ?? false;
    final total = expenses?.fold<int>(0, (sum, e) => sum + e.amountMinorUnits);

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: isReadOnly
          ? null
          : FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: Column(
        children: [
          if (isReadOnly) const ReadOnlyBanner(),
          if (total != null && expenses!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.trending_down, color: AppColors.warning, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Text('Total Recorded', style: TextStyle(color: Colors.grey.shade600)),
                      const Spacer(),
                      Text(
                        formatMoney(total, _currency),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: expenses == null
                ? const Center(child: CircularProgressIndicator())
                : expenses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_outlined, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: AppSpacing.md),
                            const Text('No expenses recorded yet — tap + to add one.'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                        itemCount: expenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final expense = expenses[index];
                          final accountName = _accountsByCode[expense.accountCode]?.name ?? expense.accountCode;
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.receipt_outlined, color: AppColors.warning, size: 18),
                              ),
                              title: Text(accountName),
                              subtitle: Text(
                                '${expense.description ?? _methodLabel(expense.method)}\n${_formatDateTime(expense.date)}',
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                formatMoney(expense.amountMinorUnits, _currency),
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.destructive),
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

String _methodLabel(ExpensePaymentMethod method) {
  switch (method) {
    case ExpensePaymentMethod.cash:
      return 'Cash';
    case ExpensePaymentMethod.bankTransfer:
      return 'Bank Transfer';
    case ExpensePaymentMethod.cheque:
      return 'Cheque';
    case ExpensePaymentMethod.card:
      return 'Card';
    case ExpensePaymentMethod.other:
      return 'Other';
  }
}

String _formatDateTime(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
    '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
