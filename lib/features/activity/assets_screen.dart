import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/whatsapp_support.dart';
import '../transport/vehicle_khata_screen.dart';
import 'asset_ledger_screen.dart';

/// Shared between Fishery (Boats) and Transport (Vehicles) — same fields,
/// different [OperatingAssetType]. See PHASES.md Section 6/12.
class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key, required this.assetType});

  final OperatingAssetType assetType;

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  List<OperatingAsset>? _assets;

  String get _label => widget.assetType == OperatingAssetType.boat ? 'Boat' : 'Vehicle';
  String get _labelPlural => widget.assetType == OperatingAssetType.boat ? 'Boats' : 'Gari Khata';
  IconData get _icon =>
      widget.assetType == OperatingAssetType.boat ? Icons.directions_boat_outlined : Icons.local_shipping_outlined;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(operatingAssetRepositoryProvider.future);
    final assets = await repo.list(businessId: businessId, type: widget.assetType);
    if (mounted) setState(() => _assets = assets);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final regController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New $_label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: '$_label name')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: regController, decoration: const InputDecoration(labelText: 'Registration number')),
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
    final repo = await ref.read(operatingAssetRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      type: widget.assetType,
      name: nameController.text,
      registrationNumber: regController.text.isEmpty ? null : regController.text,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final assets = _assets;
    return Scaffold(
      appBar: AppBar(
        title: Text(_labelPlural),
        actions: const [WhatsAppSupportButton(compact: true)],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: assets == null
          ? const Center(child: CircularProgressIndicator())
          : assets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icon, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: AppSpacing.md),
                      Text('No ${_labelPlural.toLowerCase()} yet — tap + to add one.'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: assets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Icon(_icon, color: AppColors.accent, size: 18),
                        ),
                        title: Text(asset.name),
                        subtitle: asset.registrationNumber != null ? Text(asset.registrationNumber!) : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => widget.assetType == OperatingAssetType.vehicle
                                ? VehicleKhataPager(vehicles: assets, initialIndex: index)
                                : AssetLedgerScreen(asset: asset),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
