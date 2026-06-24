import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/activity/trip.dart';
import '../../core/activity/trip_expense.dart';
import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../fishery/fish_category.dart';
import '../fishery/fish_sale.dart';
import '../transport/contract.dart';
import '../transport/trip_income.dart';

/// Shared between Fishery and Transport — status actions and the expense
/// list/add are identical for both; the catch+fish-sale section only
/// shows for fishery trips, and the trip-income section only shows for
/// transport trips. See PHASES.md Section 6/12.
class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  late Trip _trip;
  List<TripExpense>? _expenses;

  // Fishery-only state.
  List<CatchEntry>? _catches;
  List<FishSale>? _sales;
  Map<String, FishCategory> _fishCategoriesByUuid = {};

  // Transport-only state.
  List<TripIncome>? _incomes;

  int? _revenue;
  int? _expenseTotal;

  bool get _isFishery => _trip.tripType == TripType.fishery;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _load();
  }

  Future<void> _load() async {
    final tripRepo = await ref.read(tripRepositoryProvider.future);
    final expenseRepo = await ref.read(tripExpenseRepositoryProvider.future);
    final businessId = await ref.read(currentBusinessIdProvider.future);

    final reloaded = await tripRepo.findByUuid(_trip.uuid);
    final expenses = await expenseRepo.listByTrip(_trip.uuid);
    final expenseTotal = await expenseRepo.totalForTrip(_trip.uuid);

    if (_isFishery) {
      final catchRepo = await ref.read(catchRepositoryProvider.future);
      final fishSaleRepo = await ref.read(fishSaleRepositoryProvider.future);
      final categoryRepo = await ref.read(fishCategoryRepositoryProvider.future);

      final catches = await catchRepo.listByTrip(_trip.uuid);
      final sales = await fishSaleRepo.listByTrip(_trip.uuid);
      final categories = await categoryRepo.list(businessId: businessId);
      final revenue = await fishSaleRepo.totalForTrip(_trip.uuid);

      if (mounted) {
        setState(() {
          _trip = reloaded ?? _trip;
          _expenses = expenses;
          _catches = catches;
          _sales = sales;
          _fishCategoriesByUuid = {for (final c in categories) c.uuid: c};
          _revenue = revenue;
          _expenseTotal = expenseTotal;
        });
      }
    } else {
      final incomeRepo = await ref.read(tripIncomeRepositoryProvider.future);
      final incomes = await incomeRepo.listByTrip(_trip.uuid);
      final revenue = await incomeRepo.totalForTrip(_trip.uuid);

      if (mounted) {
        setState(() {
          _trip = reloaded ?? _trip;
          _expenses = expenses;
          _incomes = incomes;
          _revenue = revenue;
          _expenseTotal = expenseTotal;
        });
      }
    }
  }

  Future<void> _startTrip() async {
    final repo = await ref.read(tripRepositoryProvider.future);
    await repo.start(_trip.uuid);
    await _load();
  }

  Future<void> _completeTrip() async {
    final repo = await ref.read(tripRepositoryProvider.future);
    await repo.complete(_trip.uuid);
    await _load();
  }

  Future<void> _showAddExpenseDialog() async {
    final categories = tripExpenseCategoriesByTripType[_trip.tripType.name]!;
    final amountController = TextEditingController();
    final descController = TextEditingController();
    var category = categories.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Trip Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TripExpenseCategory>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (v) => setDialogState(() => category = v ?? categories.first),
              ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description (optional)')),
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
    final repo = await ref.read(tripExpenseRepositoryProvider.future);
    await repo.record(
      businessId: businessId,
      tripUuid: _trip.uuid,
      category: category,
      amountMinorUnits: amount,
      description: descController.text.isEmpty ? null : descController.text,
      createdBy: currentUser,
      deviceId: currentDeviceId,
    );
    await _load();
  }

  Future<FishCategory?> _pickOrCreateFishCategory() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final categoryRepo = await ref.read(fishCategoryRepositoryProvider.future);
    final categories = await categoryRepo.list(businessId: businessId);

    FishCategory? selected = categories.isNotEmpty ? categories.first : null;
    final newNameController = TextEditingController();

    if (!mounted) return null;
    final picked = await showDialog<FishCategory?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Fish Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (categories.isNotEmpty)
                DropdownButtonFormField<FishCategory>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Existing category'),
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: newNameController,
                decoration: const InputDecoration(labelText: 'Or add a new category'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (newNameController.text.isNotEmpty) {
                  final created = await categoryRepo.create(businessId: businessId, name: newNameController.text);
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                } else {
                  Navigator.pop(context, selected);
                }
              },
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );
    return picked;
  }

  Future<void> _showAddCatchDialog() async {
    final category = await _pickOrCreateFishCategory();
    if (category == null) return;

    final weightController = TextEditingController();
    final valueController = TextEditingController();

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record Catch — ${category.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightController,
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'Estimated value (optional)'),
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

    if (saved != true) return;
    final weight = double.tryParse(weightController.text) ?? 0;
    if (weight <= 0) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(catchRepositoryProvider.future);
    await repo.record(
      tripUuid: _trip.uuid,
      businessId: businessId,
      fishCategoryUuid: category.uuid,
      weightKg: weight,
      estimatedValueMinorUnits: valueController.text.isEmpty ? null : ((double.tryParse(valueController.text) ?? 0) * 100).round(),
    );
    await _load();
  }

  Future<void> _showAddFishSaleDialog() async {
    final category = await _pickOrCreateFishCategory();
    if (category == null) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);
    final customers = await partyRepo.list(businessId: businessId, type: PartyType.customer);

    final weightController = TextEditingController();
    final priceController = TextEditingController();
    var paymentMethod = FishSalePaymentMethod.cash;
    Party? selectedCustomer;

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Sell Catch — ${category.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weightController,
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Price per kg'),
                keyboardType: TextInputType.number,
              ),
              DropdownButtonFormField<FishSalePaymentMethod>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment'),
                items: FishSalePaymentMethod.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setDialogState(() => paymentMethod = v ?? FishSalePaymentMethod.cash),
              ),
              if (paymentMethod == FishSalePaymentMethod.credit)
                DropdownButtonFormField<Party>(
                  initialValue: selectedCustomer,
                  decoration: const InputDecoration(labelText: 'Customer'),
                  items: customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                  onChanged: (v) => setDialogState(() => selectedCustomer = v),
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
    final weight = double.tryParse(weightController.text) ?? 0;
    final price = ((double.tryParse(priceController.text) ?? 0) * 100).round();
    if (weight <= 0 || price <= 0) return;
    if (paymentMethod == FishSalePaymentMethod.credit && selectedCustomer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a customer for a credit sale')));
      }
      return;
    }

    final repo = await ref.read(fishSaleRepositoryProvider.future);
    try {
      await repo.create(
        businessId: businessId,
        tripUuid: _trip.uuid,
        customerUuid: selectedCustomer?.uuid,
        fishCategoryUuid: category.uuid,
        weightKg: weight,
        unitPriceMinorUnitsPerKg: price,
        paymentMethod: paymentMethod,
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

  Future<void> _showAddTripIncomeDialog() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);
    final contractRepo = await ref.read(contractRepositoryProvider.future);
    final customers = await partyRepo.list(businessId: businessId, type: PartyType.customer);
    final contracts = await contractRepo.list(businessId: businessId);

    final amountController = TextEditingController();
    final descController = TextEditingController();
    var paymentMethod = TripIncomePaymentMethod.cash;
    Party? selectedCustomer;
    Contract? selectedContract;

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Trip Income'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
              ),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description (optional)')),
              if (contracts.isNotEmpty)
                DropdownButtonFormField<Contract?>(
                  initialValue: selectedContract,
                  decoration: const InputDecoration(labelText: 'Contract (optional)'),
                  items: [
                    const DropdownMenuItem<Contract?>(value: null, child: Text('—')),
                    ...contracts.map((c) => DropdownMenuItem<Contract?>(value: c, child: Text(c.description))),
                  ],
                  onChanged: (v) => setDialogState(() => selectedContract = v),
                ),
              DropdownButtonFormField<TripIncomePaymentMethod>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment'),
                items: TripIncomePaymentMethod.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setDialogState(() => paymentMethod = v ?? TripIncomePaymentMethod.cash),
              ),
              if (paymentMethod == TripIncomePaymentMethod.credit)
                DropdownButtonFormField<Party>(
                  initialValue: selectedCustomer,
                  decoration: const InputDecoration(labelText: 'Customer'),
                  items: customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                  onChanged: (v) => setDialogState(() => selectedCustomer = v),
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
    if (paymentMethod == TripIncomePaymentMethod.credit && selectedCustomer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a customer for credit income')));
      }
      return;
    }

    final repo = await ref.read(tripIncomeRepositoryProvider.future);
    try {
      await repo.create(
        businessId: businessId,
        tripUuid: _trip.uuid,
        customerUuid: selectedCustomer?.uuid,
        contractUuid: selectedContract?.uuid,
        amountMinorUnits: amount,
        description: descController.text.isEmpty ? null : descController.text,
        paymentMethod: paymentMethod,
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
    final revenue = _revenue;
    final expenseTotal = _expenseTotal;
    final dataReady = _isFishery ? (_catches != null && _sales != null) : (_incomes != null);

    return Scaffold(
      appBar: AppBar(
        title: Text('Trip — ${_trip.status.name}'),
        actions: [
          if (_trip.status == TripStatus.planned)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton(onPressed: _startTrip, child: const Text('Start Trip')),
            ),
          if (_trip.status == TripStatus.inProgress)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton(onPressed: _completeTrip, child: const Text('Complete Trip')),
            ),
        ],
      ),
      body: expenses == null || !dataReady
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                if (revenue != null && expenseTotal != null) _buildSummaryCard(context, revenue, expenseTotal),
                const SizedBox(height: AppSpacing.xl),
                _SectionHeader(title: 'Expenses', actionLabel: 'Add Expense', onAction: _showAddExpenseDialog),
                const SizedBox(height: AppSpacing.sm),
                if (expenses.isEmpty)
                  _emptyHint('No expenses logged yet')
                else
                  ...expenses.map((e) => _Row(
                        icon: Icons.receipt_long_outlined,
                        title: e.category.name,
                        subtitle: e.description,
                        trailing: _money(e.amountMinorUnits),
                      )),
                const SizedBox(height: AppSpacing.lg),
                if (_isFishery) ..._buildFisherySections(context) else ..._buildTransportSections(context),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, int revenue, int expenseTotal) {
    final profit = revenue - expenseTotal;
    final color = profit >= 0 ? AppColors.success : AppColors.destructive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(child: _summaryStat('Revenue', revenue, AppColors.accent)),
            Expanded(child: _summaryStat('Expenses', expenseTotal, AppColors.warning)),
            Expanded(child: _summaryStat('Profit', profit, color)),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: AppSpacing.xs),
        Text(_money(value), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
      ],
    );
  }

  List<Widget> _buildFisherySections(BuildContext context) {
    final catches = _catches!;
    final sales = _sales!;
    return [
      _SectionHeader(title: 'Catch', actionLabel: 'Record Catch', onAction: _showAddCatchDialog),
      const SizedBox(height: AppSpacing.sm),
      if (catches.isEmpty)
        _emptyHint('No catch recorded yet')
      else
        ...catches.map((c) => _Row(
              icon: Icons.set_meal_outlined,
              title: _fishCategoriesByUuid[c.fishCategoryUuid]?.name ?? c.fishCategoryUuid,
              trailing: '${c.weightKg} kg',
            )),
      const SizedBox(height: AppSpacing.lg),
      _SectionHeader(title: 'Fish Sales', actionLabel: 'Sell Catch', onAction: _showAddFishSaleDialog),
      const SizedBox(height: AppSpacing.sm),
      if (sales.isEmpty)
        _emptyHint('No fish sold from this trip yet')
      else
        ...sales.map((s) => _Row(
              icon: Icons.sell_outlined,
              title: _fishCategoriesByUuid[s.fishCategoryUuid]?.name ?? s.fishCategoryUuid,
              subtitle: '${s.weightKg} kg @ ${_money(s.unitPriceMinorUnitsPerKg)}/kg  •  ${s.paymentMethod.name}',
              trailing: _money(s.totalMinorUnits),
            )),
    ];
  }

  List<Widget> _buildTransportSections(BuildContext context) {
    final incomes = _incomes!;
    return [
      _SectionHeader(title: 'Trip Income', actionLabel: 'Add Income', onAction: _showAddTripIncomeDialog),
      const SizedBox(height: AppSpacing.sm),
      if (incomes.isEmpty)
        _emptyHint('No income logged for this trip yet')
      else
        ...incomes.map((i) => _Row(
              icon: Icons.payments_outlined,
              title: i.description ?? 'Trip income',
              subtitle: i.paymentMethod.name,
              trailing: _money(i.amountMinorUnits),
            )),
    ];
  }
}

Widget _emptyHint(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    );

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actionLabel, required this.onAction});

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        OutlinedButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add, size: 16),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, required this.trailing});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppColors.accent, size: 16),
        ),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: Text(trailing, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
