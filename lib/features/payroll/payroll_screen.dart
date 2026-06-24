import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import '../../core/transaction/salary_record.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/read_only_banner.dart';

/// Lists every Party who could be on payroll (Captains/Crew/Drivers and
/// the generic `employee` role — see PartyRepository.listStaff()), their
/// salary record if any, and a "Pay Salary" action per current period.
/// See PHASES.md Phase 7.
class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  List<Party>? _staff;
  final Map<String, SalaryRecord?> _recordsByParty = {};
  final Map<String, bool> _paidThisPeriodByRecord = {};

  String get _currentPeriod {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);
    final salaryRepo = await ref.read(salaryRepositoryProvider.future);

    final staff = await partyRepo.listStaff(businessId: businessId);
    final records = await salaryRepo.listRecords(businessId: businessId);
    final recordsByParty = <String, SalaryRecord?>{};
    final paidThisPeriod = <String, bool>{};

    for (final person in staff) {
      final matchIndex = records.indexWhere((r) => r.partyUuid == person.uuid);
      final record = matchIndex == -1 ? null : records[matchIndex];
      recordsByParty[person.uuid] = record;
      if (record != null) {
        final history = await salaryRepo.paymentHistory(record.uuid);
        paidThisPeriod[record.uuid] = history.any(
          (p) => p.period == _currentPeriod,
        );
      }
    }

    if (mounted) {
      setState(() {
        _staff = staff;
        _recordsByParty
          ..clear()
          ..addAll(recordsByParty);
        _paidThisPeriodByRecord
          ..clear()
          ..addAll(paidThisPeriod);
      });
    }
  }

  Future<void> _showAddSalaryDialog(Party person) async {
    final amountController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Salary — ${person.name}'),
        content: TextField(
          controller: amountController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Monthly salary'),
          keyboardType: TextInputType.number,
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

    if (saved != true) return;
    final amount = ((double.tryParse(amountController.text) ?? 0) * 100)
        .round();
    if (amount <= 0) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(salaryRepositoryProvider.future);
    await repo.createRecord(
      businessId: businessId,
      partyUuid: person.uuid,
      amountMinorUnits: amount,
    );
    await _load();
  }

  Future<void> _paySalary(SalaryRecord record) async {
    final repo = await ref.read(salaryRepositoryProvider.future);
    try {
      await repo.paySalary(
        record: record,
        period: _currentPeriod,
        createdBy: currentUser,
        deviceId: currentDeviceId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Paid for $_currentPeriod')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = _staff;
    final isReadOnly = ref.watch(isReadOnlyProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll')),
      body: Column(
        children: [
          if (isReadOnly) const ReadOnlyBanner(),
          Expanded(
            child: staff == null
                ? const Center(child: CircularProgressIndicator())
                : staff.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'No staff yet — add Crew, Drivers, or Captains first.',
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: staff.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final person = staff[index];
                      final record = _recordsByParty[person.uuid];
                      final paidThisPeriod =
                          record != null &&
                          (_paidThisPeriodByRecord[record.uuid] ?? false);

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
                            child: const Icon(Icons.person_outline, size: 18),
                          ),
                          title: Text(person.name),
                          subtitle: Text(
                            record == null
                                ? '${person.type.name} • no salary set'
                                : '${person.type.name} • ${_money(record.amountMinorUnits)}/mo',
                          ),
                          trailing: record == null
                              ? OutlinedButton(
                                  onPressed: isReadOnly
                                      ? null
                                      : () => _showAddSalaryDialog(person),
                                  child: const Text('Set Salary'),
                                )
                              : paidThisPeriod
                              ? Chip(
                                  avatar: const Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: AppColors.success,
                                  ),
                                  label: Text('Paid ($_currentPeriod)'),
                                  backgroundColor: AppColors.success.withValues(
                                    alpha: 0.1,
                                  ),
                                  side: BorderSide.none,
                                )
                              : FilledButton(
                                  onPressed: isReadOnly
                                      ? null
                                      : () => _paySalary(record),
                                  child: Text('Pay ($_currentPeriod)'),
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
