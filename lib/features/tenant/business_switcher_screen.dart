import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../core/tenant/business.dart';

/// Lists every Business in the local database, lets the user switch the
/// active one (sets `selectedBusinessIdProvider`), and create a new one.
/// Replaces the "boots into one auto-seeded business" placeholder carried
/// since Phase 1 — see PHASES.md Phase 6.
class BusinessSwitcherScreen extends ConsumerStatefulWidget {
  const BusinessSwitcherScreen({super.key});

  @override
  ConsumerState<BusinessSwitcherScreen> createState() => _BusinessSwitcherScreenState();
}

class _BusinessSwitcherScreenState extends ConsumerState<BusinessSwitcherScreen> {
  List<Business>? _businesses;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = await ref.read(businessRepositoryProvider.future);
    final businesses = await repo.list();
    if (mounted) setState(() => _businesses = businesses);
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    var type = BusinessType.sparePartsShop;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Business'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Business name')),
              DropdownButtonFormField<BusinessType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: BusinessType.sparePartsShop, child: Text('Spare Parts Shop')),
                  DropdownMenuItem(value: BusinessType.fishery, child: Text('Fishery')),
                  DropdownMenuItem(value: BusinessType.transport, child: Text('Transport')),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? BusinessType.sparePartsShop),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (saved != true || nameController.text.isEmpty) return;

    final repo = await ref.read(businessRepositoryProvider.future);
    final business = await repo.create(name: nameController.text, type: type);

    // Grant the creating user access so the rules-enforced Firestore
    // side recognizes this business as theirs once it syncs — see
    // UserProfileRepository.grantAccess().
    final user = await ref.read(currentUserProfileProvider.future);
    if (user != null) {
      final profileRepo = ref.read(userProfileRepositoryProvider);
      await profileRepo.grantAccess(uid: user.uid, businessId: business.uuid, role: 'businessAdmin');
    }

    ref.read(selectedBusinessIdProvider.notifier).state = business.uuid;
    await _load();
    if (mounted) Navigator.of(context).pop(); // back out to the now-switched app shell
  }

  @override
  Widget build(BuildContext context) {
    final businesses = _businesses;
    final activeId = ref.watch(currentBusinessIdProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Switch Business')),
      floatingActionButton: FloatingActionButton(onPressed: _showCreateDialog, child: const Icon(Icons.add)),
      body: businesses == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: businesses.length,
              itemBuilder: (context, index) {
                final business = businesses[index];
                final isActive = business.uuid == activeId;
                return ListTile(
                  leading: Icon(_iconFor(business.type), color: isActive ? Theme.of(context).colorScheme.primary : null),
                  title: Text(business.name),
                  subtitle: Text(_labelFor(business.type)),
                  trailing: isActive ? const Icon(Icons.check_circle, color: Colors.green) : null,
                  selected: isActive,
                  onTap: () {
                    ref.read(selectedBusinessIdProvider.notifier).state = business.uuid;
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
    );
  }
}

IconData _iconFor(BusinessType type) {
  switch (type) {
    case BusinessType.sparePartsShop:
      return Icons.store_outlined;
    case BusinessType.fishery:
      return Icons.directions_boat_outlined;
    case BusinessType.transport:
      return Icons.local_shipping_outlined;
  }
}

String _labelFor(BusinessType type) {
  switch (type) {
    case BusinessType.sparePartsShop:
      return 'Spare Parts Shop';
    case BusinessType.fishery:
      return 'Fishery';
    case BusinessType.transport:
      return 'Transport';
  }
}
