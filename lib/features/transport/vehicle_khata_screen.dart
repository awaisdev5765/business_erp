import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/party/party.dart';
import '../../core/party/party_ledger_screen.dart';
import '../../core/system/providers.dart';
import '../../shared/currency/currency.dart';
import '../../shared/pdf/transport_pdf.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/transport_ui.dart';
import '../../shared/widgets/whatsapp_support.dart';
import 'vehicle_khata_line.dart';

/// Swipe between gaaris like Excel sheet tabs.
class VehicleKhataPager extends StatelessWidget {
  const VehicleKhataPager({super.key, required this.vehicles, required this.initialIndex});

  final List<OperatingAsset> vehicles;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: PageController(initialPage: initialIndex),
      itemCount: vehicles.length,
      itemBuilder: (context, index) => VehicleKhataScreen(
        vehicle: vehicles[index],
        vehicleIndex: index,
        vehicleCount: vehicles.length,
      ),
    );
  }
}

class VehicleKhataScreen extends ConsumerStatefulWidget {
  const VehicleKhataScreen({
    super.key,
    required this.vehicle,
    this.vehicleIndex,
    this.vehicleCount,
  });

  final OperatingAsset vehicle;
  final int? vehicleIndex;
  final int? vehicleCount;

  @override
  ConsumerState<VehicleKhataScreen> createState() => _VehicleKhataScreenState();
}

class _VehicleKhataScreenState extends ConsumerState<VehicleKhataScreen> {
  List<VehicleKhataRow>? _rows;
  String? _currency;
  String? _businessName;
  DateTime? _from;
  DateTime? _to;

  String get _title => widget.vehicle.registrationNumber ?? widget.vehicle.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VehicleKhataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.uuid != widget.vehicle.uuid) _load();
  }

  Future<void> _load() async {
    final khata = await ref.read(vehicleKhataRepositoryProvider.future);
    final business = await ref.read(currentBusinessProvider.future);
    final rows = await khata.statement(widget.vehicle.uuid);
    if (mounted) {
      setState(() {
        _rows = rows;
        _currency = business.baseCurrency;
        _businessName = business.name;
      });
    }
  }

  bool get _hasOpening => _rows?.any((r) => r.line.kind == VehicleKhataKind.opening) ?? false;

  List<VehicleKhataRow> get _filtered {
    final rows = _rows;
    if (rows == null) return const [];
    if (_from == null || _to == null) return rows;
    final end = DateTime(_to!.year, _to!.month, _to!.day).add(const Duration(days: 1));
    return rows.where((r) => !r.line.date.isBefore(_from!) && r.line.date.isBefore(end)).toList();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
    }
  }

  Future<void> _print() async {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;
    await TransportPdf.printGariKhata(
      businessName: _businessName ?? 'Business',
      vehicleLabel: _title,
      rows: rows,
      money: (m) => formatMoney(m, _currency),
    );
  }

  Future<void> _addOrEdit({VehicleKhataLine? existing, required bool kharcha}) async {
    if (existing?.sourceType == 'MonthlySettlement') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Month hisaab ki entry yahan change nahi hoti')),
      );
      return;
    }
    var date = existing?.date ?? DateTime.now();
    final tafseelController = TextEditingController(text: existing?.tafseel ?? '');
    final amountController = TextEditingController(
      text: existing == null
          ? ''
          : ((existing.kharchaMinorUnits > 0 ? existing.kharchaMinorUnits : existing.jamaMinorUnits) / 100)
              .toStringAsFixed(0),
    );
    final isKharcha = existing?.kind == VehicleKhataKind.kharcha || (existing == null && kharcha);

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null
                      ? (isKharcha ? 'Kharcha likho' : 'Jama Raqam likho')
                      : 'Entry edit karein',
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
                TextField(
                  controller: tafseelController,
                  style: const TextStyle(fontSize: 18),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Tafseel', hintText: 'Local, diesel, peshgi…'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TafseelChips(
                  onSelected: (v) => setDialogState(() => tafseelController.text = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: amountController,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Raqam'),
                  keyboardType: TextInputType.number,
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
      ),
    );

    if (saved != true) return;
    final amount = ((double.tryParse(amountController.text.trim()) ?? 0) * 100).round();
    if (amount <= 0 || tafseelController.text.trim().isEmpty) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(vehicleKhataRepositoryProvider.future);
    try {
      if (existing != null) {
        await repo.updateManual(
          uuid: existing.uuid,
          tafseel: tafseelController.text,
          amountMinorUnits: amount,
          date: date,
          createdBy: currentUser,
          deviceId: currentDeviceId,
        );
      } else if (isKharcha) {
        await repo.addKharcha(
          businessId: businessId,
          vehicleUuid: widget.vehicle.uuid,
          tafseel: tafseelController.text,
          amountMinorUnits: amount,
          createdBy: currentUser,
          deviceId: currentDeviceId,
          date: date,
        );
      } else {
        await repo.addJama(
          businessId: businessId,
          vehicleUuid: widget.vehicle.uuid,
          tafseel: tafseelController.text,
          amountMinorUnits: amount,
          createdBy: currentUser,
          deviceId: currentDeviceId,
          date: date,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(VehicleKhataLine line) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Ye entry delete ho jayegi:\n${line.tafseel}'),
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
    final repo = await ref.read(vehicleKhataRepositoryProvider.future);
    try {
      await repo.deleteManual(uuid: line.uuid, deletedBy: currentUser);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _setOpening() async {
    final amountController = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pichla Baqaya', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: amountController,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Opening', helperText: 'Minus (-) agar udhaar ho'),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 52,
              child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final amount = ((double.tryParse(amountController.text.trim()) ?? 0) * 100).round();
    if (amount == 0) return;
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(vehicleKhataRepositoryProvider.future);
    try {
      await repo.setOpening(businessId: businessId, vehicleUuid: widget.vehicle.uuid, amountMinorUnits: amount);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openCompanyPayment() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final parties = await ref.read(partyRepositoryProvider.future);
    final companies = await parties.list(businessId: businessId, type: PartyType.customer);
    if (!mounted) return;
    if (companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle company add karein')));
      return;
    }
    final company = await showModalBottomSheet<Party>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        children: [
          const ListTile(title: Text('Company payment', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final c in companies)
            ListTile(
              title: Text(c.name, style: const TextStyle(fontSize: 16)),
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
    if (company == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyLedgerScreen(party: company)));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final currency = _currency;
    final balance = _rows == null || _rows!.isEmpty ? 0 : _rows!.last.runningBalanceMinorUnits;
    final newestFirst = rows.reversed.toList();
    final idx = widget.vehicleIndex;
    final count = widget.vehicleCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (idx != null && count != null)
              Text('Gaari ${idx + 1}/$count — swipe left/right', style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Print', onPressed: _print, icon: const Icon(Icons.print_outlined)),
          IconButton(tooltip: 'Company payment', onPressed: _openCompanyPayment, icon: const Icon(Icons.payments_outlined)),
          const WhatsAppSupportButton(compact: true),
          if (!_hasOpening) TextButton(onPressed: _setOpening, child: const Text('Opening')),
        ],
      ),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.primary,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Raqam / Baqaya', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(balance, currency),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32),
                      ),
                    ],
                  ),
                ),
                DateRangeFilterBar(
                  from: _from,
                  to: _to,
                  onPick: _pickRange,
                  onClear: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                ),
                Expanded(
                  child: newestFirst.isEmpty
                      ? const Center(child: Text('Koi entry nahi — neeche Kharcha / Jama', style: TextStyle(fontSize: 16)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
                          itemCount: newestFirst.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final row = newestFirst[index];
                            final line = row.line;
                            final isKharcha = line.kharchaMinorUnits > 0;
                            final amount = isKharcha ? line.kharchaMinorUnits : line.jamaMinorUnits;
                            final locked = line.sourceType == 'MonthlySettlement' || line.kind == VehicleKhataKind.opening;
                            return Card(
                              child: InkWell(
                                onTap: locked ? null : () => _addOrEdit(existing: line, kharcha: isKharcha),
                                onLongPress: locked ? null : () => _delete(line),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(_formatDate(line.date), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                          const Spacer(),
                                          Text(
                                            isKharcha
                                                ? 'Kharcha'
                                                : (line.kind == VehicleKhataKind.opening ? 'Opening' : 'Jama'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: isKharcha ? AppColors.destructive : AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(line.tafseel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            '${isKharcha ? '−' : '+'} ${formatMoney(amount, currency)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 20,
                                              color: isKharcha ? AppColors.destructive : AppColors.success,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            'Baqaya ${formatMoney(row.runningBalanceMinorUnits, currency)}',
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                      if (!locked)
                                        Text('Tap = edit · Long press = delete', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _addOrEdit(kharcha: true),
                    icon: const Icon(Icons.remove),
                    label: const Text('Kharcha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _addOrEdit(kharcha: false),
                    icon: const Icon(Icons.add),
                    label: const Text('Jama', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
