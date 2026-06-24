import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/fixed_asset.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

class FixedAssetsScreen extends ConsumerStatefulWidget {
  const FixedAssetsScreen({super.key});

  @override
  ConsumerState<FixedAssetsScreen> createState() => _FixedAssetsScreenState();
}

class _FixedAssetsScreenState extends ConsumerState<FixedAssetsScreen> {
  List<FixedAsset>? _assets;
  final Map<String, int> _bookValues = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(fixedAssetRepositoryProvider.future);
    final assets = await repo.list(businessId: businessId);

    final bookValues = <String, int>{};
    for (final asset in assets) {
      bookValues[asset.uuid] = await repo.bookValue(asset);
    }

    if (mounted) {
      setState(() {
        _assets = assets;
        _bookValues
          ..clear()
          ..addAll(bookValues);
      });
    }
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final costController = TextEditingController();
    final lifeController = TextEditingController(text: '36');
    final salvageController = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Fixed Asset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: costController,
              decoration: const InputDecoration(labelText: 'Acquisition cost'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: lifeController,
              decoration: const InputDecoration(labelText: 'Useful life (months)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: salvageController,
              decoration: const InputDecoration(labelText: 'Salvage value'),
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
    final repo = await ref.read(fixedAssetRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      name: nameController.text,
      acquisitionDate: DateTime.now(),
      acquisitionCostMinorUnits: ((double.tryParse(costController.text) ?? 0) * 100).round(),
      usefulLifeMonths: int.tryParse(lifeController.text) ?? 36,
      salvageValueMinorUnits: ((double.tryParse(salvageController.text) ?? 0) * 100).round(),
    );
    await _load();
  }

  Future<void> _postDepreciation(FixedAsset asset) async {
    final now = DateTime.now();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final service = await ref.read(depreciationServiceProvider.future);
    try {
      await service.postMonthlyDepreciation(
        fixedAssetUuid: asset.uuid,
        period: period,
        createdBy: currentUser,
        deviceId: currentDeviceId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Depreciation posted for $period')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = _assets;
    return Scaffold(
      appBar: AppBar(title: const Text('Fixed Assets')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: assets == null
          ? const Center(child: CircularProgressIndicator())
          : assets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.precision_manufacturing_outlined, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: AppSpacing.md),
                      const Text('No fixed assets yet — tap + to add one.'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: assets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    final bookValue = _bookValues[asset.uuid];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.precision_manufacturing_outlined, color: AppColors.accent, size: 18),
                        ),
                        title: Text(asset.name),
                        subtitle: Text(
                          'Cost: ${_money(asset.acquisitionCostMinorUnits)}  •  '
                          '${_money(asset.monthlyDepreciationMinorUnits)}/mo  •  '
                          'Book value: ${bookValue != null ? _money(bookValue) : '…'}',
                        ),
                        trailing: OutlinedButton(
                          onPressed: () => _postDepreciation(asset),
                          child: const Text('Post Depreciation'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
