import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/party/party.dart';
import '../../core/party/party_ledger_screen.dart';
import '../../core/system/providers.dart';
import '../../shared/currency/currency.dart';
import '../../shared/pdf/transport_pdf.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/whatsapp_support.dart';
import 'monthly_settlement.dart';
import 'monthly_settlement_repository.dart';
import 'weight_entry.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Month-end: total weight × rate = company bill + vehicle khata.
class MonthHisaabScreen extends ConsumerStatefulWidget {
  const MonthHisaabScreen({super.key});

  @override
  ConsumerState<MonthHisaabScreen> createState() => _MonthHisaabScreenState();
}

class _MonthHisaabScreenState extends ConsumerState<MonthHisaabScreen> {
  late int _year;
  late int _month;
  List<Party> _companies = [];
  Party? _company;
  List<WeightEntry> _pending = [];
  List<WeightEntry> _settledEntries = [];
  MonthlySettlement? _existing;
  Map<String, OperatingAsset> _vehicles = {};
  final _rateController = TextEditingController();
  String? _currency;
  String? _businessName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _bootstrap();
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final parties = await ref.read(partyRepositoryProvider.future);
    final assets = await ref.read(operatingAssetRepositoryProvider.future);
    final business = await ref.read(currentBusinessProvider.future);
    final companies = await parties.list(businessId: businessId, type: PartyType.customer);
    final vehicles = await assets.list(businessId: businessId, type: OperatingAssetType.vehicle);

    if (!mounted) return;
    setState(() {
      _companies = companies;
      _company = companies.isEmpty ? null : companies.first;
      _vehicles = {for (final v in vehicles) v.uuid: v};
      _currency = business.baseCurrency;
      _businessName = business.name;
    });
    await _reloadMonth();
  }

  Future<void> _reloadMonth() async {
    final company = _company;
    if (company == null) {
      setState(() {
        _pending = [];
        _settledEntries = [];
        _existing = null;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final weightRepo = await ref.read(weightEntryRepositoryProvider.future);
    final settleRepo = await ref.read(monthlySettlementRepositoryProvider.future);
    final contractRepo = await ref.read(contractRepositoryProvider.future);

    final pending = await weightRepo.listUnsettledForMonth(
      businessId: businessId,
      companyUuid: company.uuid,
      year: _year,
      month: _month,
    );
    final existing = await settleRepo.findForMonth(
      businessId: businessId,
      companyUuid: company.uuid,
      year: _year,
      month: _month,
    );
    final settledEntries =
        existing == null ? <WeightEntry>[] : await weightRepo.listBySettlement(existing.uuid);
    final contract = await contractRepo.findForCustomer(businessId: businessId, customerUuid: company.uuid);

    if (!mounted) return;
    if (existing != null) {
      _rateController.text = (existing.ratePerTonMinorUnits / 100).toStringAsFixed(0);
    } else if (contract?.ratePerTonMinorUnits != null) {
      _rateController.text = (contract!.ratePerTonMinorUnits! / 100).toStringAsFixed(0);
    } else {
      _rateController.clear();
    }
    setState(() {
      _pending = pending;
      _settledEntries = settledEntries;
      _existing = existing;
      _loading = false;
    });
  }

  String _vehicleLabel(String uuid) {
    final v = _vehicles[uuid];
    if (v == null) return 'Gaari';
    return v.registrationNumber ?? v.name;
  }

  Future<void> _printBill() async {
    final company = _company;
    final existing = _existing;
    if (company == null || existing == null) return;
    await TransportPdf.printMonthBill(
      businessName: _businessName ?? 'Business',
      companyName: company.name,
      year: _year,
      month: _month,
      ratePerTonMinorUnits: existing.ratePerTonMinorUnits,
      totalWeightKg: existing.totalWeightKg,
      amountMinorUnits: existing.amountMinorUnits,
      entries: _settledEntries,
      vehicleLabel: _vehicleLabel,
      money: (m) => formatMoney(m, _currency),
    );
  }

  Future<void> _settle() async {
    final company = _company;
    if (company == null) return;
    final rate = ((double.tryParse(_rateController.text.trim()) ?? 0) * 100).round();
    if (rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rate per ton likhein')));
      return;
    }

    final totalWeightKg = _pending.fold<double>(0, (sum, e) => sum + e.weightKg);
    final previewAmount = amountForWeight(weightKg: totalWeightKg, ratePerTonMinorUnits: rate);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Month settle?'),
        content: Text(
          '${_monthNames[_month - 1]} $_year — ${company.name}\n\n'
          'Weight: ${_formatKg(totalWeightKg)} kg\n'
          'Rate: ${formatMoney(rate, _currency)} / ton\n'
          'Bill: ${formatMoney(previewAmount, _currency)}\n\n'
          'Company ke khate pe bill lagega aur har gaari pe Jama.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nahi')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Haan, Settle')),
        ],
      ),
    );
    if (confirmed != true) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(monthlySettlementRepositoryProvider.future);
    try {
      await repo.settle(
        businessId: businessId,
        companyUuid: company.uuid,
        year: _year,
        month: _month,
        ratePerTonMinorUnits: rate,
        createdBy: currentUser,
        deviceId: currentDeviceId,
        companyName: company.name,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Month hisaab save ho gaya')));
      }
      await _reloadMonth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openPayment() async {
    final company = _company;
    if (company == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyLedgerScreen(party: company)));
  }

  @override
  Widget build(BuildContext context) {
    final currency = _currency;
    final totalWeightKg = _pending.fold<double>(0, (sum, e) => sum + e.weightKg);
    final rate = ((double.tryParse(_rateController.text.trim()) ?? 0) * 100).round();
    final previewAmount = amountForWeight(weightKg: totalWeightKg, ratePerTonMinorUnits: rate);
    final years = [DateTime.now().year, DateTime.now().year - 1];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Month Hisaab'),
        actions: [
          if (_existing != null) IconButton(tooltip: 'Print bill', onPressed: _printBill, icon: const Icon(Icons.print_outlined)),
          if (_company != null)
            IconButton(tooltip: 'Company payment', onPressed: _openPayment, icon: const Icon(Icons.payments_outlined)),
          const WhatsAppSupportButton(compact: true),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _month,
                        decoration: const InputDecoration(labelText: 'Mahina'),
                        items: [
                          for (var i = 1; i <= 12; i++)
                            DropdownMenuItem(value: i, child: Text(_monthNames[i - 1])),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _month = v);
                          _reloadMonth();
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _year,
                        decoration: const InputDecoration(labelText: 'Saal'),
                        items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _year = v);
                          _reloadMonth();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_companies.isEmpty)
                  const Text('Pehle Customers mein company add karein.', style: TextStyle(fontSize: 16))
                else
                  DropdownButtonFormField<Party>(
                    initialValue: _company,
                    decoration: const InputDecoration(labelText: 'Company'),
                    items: _companies.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                    onChanged: (v) {
                      setState(() => _company = v);
                      _rateController.clear();
                      _reloadMonth();
                    },
                  ),
                const SizedBox(height: AppSpacing.lg),
                if (_existing != null) ...[
                  Card(
                    color: AppColors.primary,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settled — ${_monthNames[_month - 1]} $_year',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            formatMoney(_existing!.amountMinorUnits, currency),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatKg(_existing!.totalWeightKg)} kg × ${formatMoney(_existing!.ratePerTonMinorUnits, currency)}/ton',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            'Company khata + gaari Jama dono update ho chuke.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _printBill,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print / PDF bill'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _openPayment,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Company payment likho'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Bills is mahine', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  ..._settledEntries.map((e) {
                    return Card(
                      child: ListTile(
                        title: Text('${_vehicleLabel(e.vehicleUuid)}  •  ${_formatKg(e.weightKg)} kg',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        subtitle: Text(
                          '${e.date.day.toString().padLeft(2, '0')}/${e.date.month.toString().padLeft(2, '0')}/${e.date.year}',
                        ),
                      ),
                    );
                  }),
                ] else ...[
                  TextField(
                    controller: _rateController,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(labelText: 'Rate per ton', helperText: 'Jaise Excel: per ton rate'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total weight', style: TextStyle(color: Colors.grey.shade600)),
                          Text(_formatKg(totalWeightKg), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28)),
                          Text('kg', style: TextStyle(color: Colors.grey.shade600)),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Bill preview', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(
                                rate > 0 ? formatMoney(previewAmount, currency) : '—',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _pending.isEmpty ? null : _settle,
                      child: const Text('Settle Month', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _pending.isEmpty ? 'Is mahine pending weight nahi.' : 'Pending bills',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._pending.map((e) {
                    return Card(
                      child: ListTile(
                        title: Text('${_vehicleLabel(e.vehicleUuid)}  •  ${_formatKg(e.weightKg)} kg',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        subtitle: Text(
                          '${e.date.day.toString().padLeft(2, '0')}/${e.date.month.toString().padLeft(2, '0')}/${e.date.year}',
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

String _formatKg(double kg) => kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1);
