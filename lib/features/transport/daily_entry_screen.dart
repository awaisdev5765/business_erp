import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/party/party.dart';
import '../../core/party/party_ledger_screen.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/transport_ui.dart';
import '../../shared/widgets/whatsapp_support.dart';
import 'weight_entry.dart';

/// Company Bills — Excel parity: Date | Vehicle No | Weight (kg) | Company.
class DailyEntryScreen extends ConsumerStatefulWidget {
  const DailyEntryScreen({super.key});

  @override
  ConsumerState<DailyEntryScreen> createState() => _DailyEntryScreenState();
}

class _DailyEntryScreenState extends ConsumerState<DailyEntryScreen> {
  List<WeightEntry>? _entries;
  Map<String, OperatingAsset> _vehicles = {};
  Map<String, Party> _companies = {};
  String? _filterVehicleUuid;
  String? _filterCompanyUuid;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final weightRepo = await ref.read(weightEntryRepositoryProvider.future);
    final assets = await ref.read(operatingAssetRepositoryProvider.future);
    final parties = await ref.read(partyRepositoryProvider.future);

    DateTime? toExclusive;
    if (_to != null) {
      toExclusive = DateTime(_to!.year, _to!.month, _to!.day).add(const Duration(days: 1));
    }

    final entries = await weightRepo.list(
      businessId: businessId,
      vehicleUuid: _filterVehicleUuid,
      companyUuid: _filterCompanyUuid,
      from: _from,
      to: toExclusive,
    );
    final vehicles = await assets.list(businessId: businessId, type: OperatingAssetType.vehicle);
    final companies = await parties.list(businessId: businessId, type: PartyType.customer);

    if (mounted) {
      setState(() {
        _entries = entries;
        _vehicles = {for (final v in vehicles) v.uuid: v};
        _companies = {for (final c in companies) c.uuid: c};
      });
    }
  }

  String _vehicleLabel(OperatingAsset v) => v.registrationNumber ?? v.name;

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      await _load();
    }
  }

  Future<void> _showEditor({WeightEntry? existing}) async {
    if (_vehicles.isEmpty || _companies.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _vehicles.isEmpty
                  ? 'Pehle Gari Khata mein gaari add karein'
                  : 'Pehle Customers mein company add karein',
            ),
          ),
        );
      }
      return;
    }

    if (existing?.isSettled == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settled bill change nahi ho sakti')),
      );
      return;
    }

    var vehicle = existing != null
        ? (_vehicles[existing.vehicleUuid] ?? _vehicles.values.first)
        : _vehicles.values.first;
    var company = existing != null
        ? (_companies[existing.companyUuid] ?? _companies.values.first)
        : _companies.values.first;
    var date = existing?.date ?? DateTime.now();
    final weightController = TextEditingController(
      text: existing == null ? '' : _formatKg(existing.weightKg),
    );

    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Naya Bill' : 'Bill Edit',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 22),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date', style: TextStyle(fontSize: 16)),
                subtitle: Text(_formatDate(date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
              DropdownButtonFormField<OperatingAsset>(
                initialValue: vehicle,
                decoration: const InputDecoration(labelText: 'Gaari No'),
                items: _vehicles.values
                    .map((v) => DropdownMenuItem(value: v, child: Text(_vehicleLabel(v), style: const TextStyle(fontSize: 16))))
                    .toList(),
                onChanged: (v) => setDialogState(() => vehicle = v ?? vehicle),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<Party>(
                initialValue: company,
                decoration: const InputDecoration(labelText: 'Company'),
                items: _companies.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(fontSize: 16))))
                    .toList(),
                onChanged: (v) => setDialogState(() => company = v ?? company),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: weightController,
                autofocus: existing == null,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Weight (kg)', hintText: '37450'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true) return;
    final weight = double.tryParse(weightController.text.trim().replaceAll(',', '')) ?? 0;
    if (weight <= 0) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(weightEntryRepositoryProvider.future);
    try {
      if (existing != null) {
        await repo.update(
          uuid: existing.uuid,
          vehicleUuid: vehicle.uuid,
          companyUuid: company.uuid,
          weightKg: weight,
          date: date,
        );
      } else {
        await repo.create(
          businessId: businessId,
          vehicleUuid: vehicle.uuid,
          companyUuid: company.uuid,
          weightKg: weight,
          date: date,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(WeightEntry entry) async {
    if (entry.isSettled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settled bill delete nahi ho sakti')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete?'),
        content: Text(
          '${_formatDate(entry.date)} — ${_formatKg(entry.weightKg)} kg\nDelete kar dein?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nahi')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(weightEntryRepositoryProvider.future);
    try {
      await repo.delete(entry.uuid);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openPayment(Party company) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyLedgerScreen(party: company)));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Bills'),
        actions: const [WhatsAppSupportButton(compact: true)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Naya Bill'),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _filterVehicleUuid,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Gaari', isDense: true),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Sab')),
                            ..._vehicles.values.map(
                              (v) => DropdownMenuItem<String?>(
                                value: v.uuid,
                                child: Text(_vehicleLabel(v), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _filterVehicleUuid = v);
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: _filterCompanyUuid,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Company', isDense: true),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Sab')),
                            ..._companies.values.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c.uuid,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _filterCompanyUuid = v);
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                DateRangeFilterBar(
                  from: _from,
                  to: _to,
                  onPick: _pickRange,
                  onClear: () {
                    setState(() {
                      _from = null;
                      _to = null;
                    });
                    _load();
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Text(
                              'Abhi koi bill nahi.\nNeeche “Naya Bill” dabao.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final e = entries[index];
                            final vehicle = _vehicles[e.vehicleUuid];
                            final company = _companies[e.companyUuid];
                            return Card(
                              child: InkWell(
                                onTap: e.isSettled ? null : () => _showEditor(existing: e),
                                onLongPress: e.isSettled ? null : () => _delete(e),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(_formatDate(e.date), style: TextStyle(color: Colors.grey.shade600)),
                                          const Spacer(),
                                          Text(
                                            e.isSettled ? 'Settled' : 'Pending',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: e.isSettled ? AppColors.success : AppColors.warning,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        vehicle == null ? '—' : _vehicleLabel(vehicle),
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                                      ),
                                      Text(company?.name ?? '—', style: const TextStyle(fontSize: 15)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            '${_formatKg(e.weightKg)} kg',
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                                          ),
                                          const Spacer(),
                                          if (company != null)
                                            TextButton(
                                              onPressed: () => _openPayment(company),
                                              child: const Text('Payment'),
                                            ),
                                        ],
                                      ),
                                      if (!e.isSettled)
                                        Text(
                                          'Tap = edit · Long press = delete',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                    ],
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

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _formatKg(double kg) => kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1);
