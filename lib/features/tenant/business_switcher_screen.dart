import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../core/tenant/business.dart';

/// Lists every Business the signed-in user can access — every business
/// for a Super Admin, only the ones granted to staff otherwise (see
/// `accessibleBusinessesProvider`) — lets them switch the active one
/// (sets `selectedBusinessIdProvider`), and (Super Admin only) create a
/// new one. Replaces the "boots into one auto-seeded business"
/// placeholder carried since Phase 1 — see PHASES.md Phase 6.
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
    final businesses = await ref.read(accessibleBusinessesProvider.future);
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

  Future<void> _confirmArchive(Business business) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Business?'),
        content: Text(
          '"${business.name}" will disappear from the switcher and nav for everyone. '
          "Its ledger history isn't deleted — this can't be undone from the app, though.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = await ref.read(businessRepositoryProvider.future);
    await repo.archive(business.uuid);

    // If the archived business was the active one, fall back to
    // whatever's now first in the accessible list rather than leaving
    // selectedBusinessIdProvider pointing at a now-hidden business.
    if (ref.read(selectedBusinessIdProvider) == business.uuid || ref.read(currentBusinessIdProvider).valueOrNull == business.uuid) {
      ref.read(selectedBusinessIdProvider.notifier).state = null;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final businesses = _businesses;
    final activeId = ref.watch(currentBusinessIdProvider).valueOrNull;
    final isSuperAdmin = ref.watch(currentUserProfileProvider).valueOrNull?.isSuperAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Switch Business')),
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton(onPressed: _showCreateDialog, child: const Icon(Icons.add))
          : null,
      body: businesses != null && businesses.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isSuperAdmin
                      ? 'No business yet — tap + to create one.'
                      : 'No business assigned yet. Contact your administrator.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : businesses == null
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive) const Icon(Icons.check_circle, color: Colors.green),
                      if (isSuperAdmin)
                        IconButton(
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          tooltip: 'Archive',
                          onPressed: () => _confirmArchive(business),
                        ),
                    ],
                  ),
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
