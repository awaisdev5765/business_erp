import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/system/providers.dart';
import 'boat_ledger_screen.dart';

class BoatsScreen extends ConsumerStatefulWidget {
  const BoatsScreen({super.key});

  @override
  ConsumerState<BoatsScreen> createState() => _BoatsScreenState();
}

class _BoatsScreenState extends ConsumerState<BoatsScreen> {
  List<OperatingAsset>? _boats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(operatingAssetRepositoryProvider.future);
    final boats = await repo.list(businessId: businessId, type: OperatingAssetType.boat);
    if (mounted) setState(() => _boats = boats);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final regController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Boat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Boat name')),
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
      type: OperatingAssetType.boat,
      name: nameController.text,
      registrationNumber: regController.text.isEmpty ? null : regController.text,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final boats = _boats;
    return Scaffold(
      appBar: AppBar(title: const Text('Boats')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: boats == null
          ? const Center(child: CircularProgressIndicator())
          : boats.isEmpty
              ? const Center(child: Text('No boats yet — tap + to add one.'))
              : ListView.builder(
                  itemCount: boats.length,
                  itemBuilder: (context, index) {
                    final boat = boats[index];
                    return ListTile(
                      leading: const Icon(Icons.directions_boat_outlined),
                      title: Text(boat.name),
                      subtitle: boat.registrationNumber != null ? Text(boat.registrationNumber!) : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => BoatLedgerScreen(boat: boat)),
                      ),
                    );
                  },
                ),
    );
  }
}
