import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/activity/trip.dart';
import '../../core/asset/operating_asset.dart';
import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import 'trip_detail_screen.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  List<Trip>? _trips;
  Map<String, OperatingAsset> _boatsByUuid = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final tripRepo = await ref.read(tripRepositoryProvider.future);
    final assetRepo = await ref.read(operatingAssetRepositoryProvider.future);

    final trips = await tripRepo.list(businessId: businessId, tripType: TripType.fishery);
    final boats = await assetRepo.list(businessId: businessId, type: OperatingAssetType.boat);

    if (mounted) {
      setState(() {
        _trips = trips;
        _boatsByUuid = {for (final b in boats) b.uuid: b};
      });
    }
  }

  Future<void> _showCreateDialog() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final assetRepo = await ref.read(operatingAssetRepositoryProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);

    final boats = await assetRepo.list(businessId: businessId, type: OperatingAssetType.boat);
    final captains = await partyRepo.list(businessId: businessId, type: PartyType.captain);

    if (boats.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a boat first')));
      }
      return;
    }

    OperatingAsset selectedBoat = boats.first;
    Party? selectedCaptain;

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Trip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<OperatingAsset>(
                initialValue: selectedBoat,
                decoration: const InputDecoration(labelText: 'Boat'),
                items: boats.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
                onChanged: (v) => setDialogState(() => selectedBoat = v ?? boats.first),
              ),
              DropdownButtonFormField<Party?>(
                initialValue: selectedCaptain,
                decoration: const InputDecoration(labelText: 'Captain (optional)'),
                items: [
                  const DropdownMenuItem<Party?>(value: null, child: Text('—')),
                  ...captains.map((c) => DropdownMenuItem<Party?>(value: c, child: Text(c.name))),
                ],
                onChanged: (v) => setDialogState(() => selectedCaptain = v),
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

    final tripRepo = await ref.read(tripRepositoryProvider.future);
    await tripRepo.create(
      businessId: businessId,
      tripType: TripType.fishery,
      assetUuid: selectedBoat.uuid,
      captainUuid: selectedCaptain?.uuid,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      floatingActionButton: FloatingActionButton(onPressed: _showCreateDialog, child: const Icon(Icons.add)),
      body: trips == null
          ? const Center(child: CircularProgressIndicator())
          : trips.isEmpty
              ? const Center(child: Text('No trips yet — tap + to plan one.'))
              : ListView.builder(
                  itemCount: trips.length,
                  itemBuilder: (context, index) {
                    final trip = trips[index];
                    final boat = _boatsByUuid[trip.assetUuid];
                    return ListTile(
                      leading: Icon(_statusIcon(trip.status)),
                      title: Text(boat?.name ?? trip.assetUuid),
                      subtitle: Text('${trip.status.name}  •  ${_formatDate(trip.startDate)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)),
                        );
                        await _load();
                      },
                    );
                  },
                ),
    );
  }
}

IconData _statusIcon(TripStatus status) {
  switch (status) {
    case TripStatus.planned:
      return Icons.schedule;
    case TripStatus.inProgress:
      return Icons.sailing;
    case TripStatus.completed:
      return Icons.check_circle_outline;
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
