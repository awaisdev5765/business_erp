import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/activity/trip.dart';
import '../../core/asset/operating_asset.dart';
import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import 'trip_detail_screen.dart';

/// Shared between Fishery and Transport — same Trip lifecycle, just a
/// different asset type (boat/vehicle) and crew type (captain/driver).
/// See PHASES.md Section 6/12.
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key, required this.tripType});

  final TripType tripType;

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  List<Trip>? _trips;
  Map<String, OperatingAsset> _assetsByUuid = {};

  OperatingAssetType get _assetType =>
      widget.tripType == TripType.fishery ? OperatingAssetType.boat : OperatingAssetType.vehicle;

  PartyType get _crewType => widget.tripType == TripType.fishery ? PartyType.captain : PartyType.driver;

  String get _assetLabel => widget.tripType == TripType.fishery ? 'Boat' : 'Vehicle';

  String get _crewLabel => widget.tripType == TripType.fishery ? 'Captain' : 'Driver';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final tripRepo = await ref.read(tripRepositoryProvider.future);
    final assetRepo = await ref.read(operatingAssetRepositoryProvider.future);

    final trips = await tripRepo.list(businessId: businessId, tripType: widget.tripType);
    final assetList = await assetRepo.list(businessId: businessId, type: _assetType);

    if (mounted) {
      setState(() {
        _trips = trips;
        _assetsByUuid = {for (final a in assetList) a.uuid: a};
      });
    }
  }

  Future<void> _showCreateDialog() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final assetRepo = await ref.read(operatingAssetRepositoryProvider.future);
    final partyRepo = await ref.read(partyRepositoryProvider.future);

    final assetList = await assetRepo.list(businessId: businessId, type: _assetType);
    final crew = await partyRepo.list(businessId: businessId, type: _crewType);

    if (assetList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add a $_assetLabel first')));
      }
      return;
    }

    OperatingAsset selectedAsset = assetList.first;
    Party? selectedCrew;

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
                initialValue: selectedAsset,
                decoration: InputDecoration(labelText: _assetLabel),
                items: assetList.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                onChanged: (v) => setDialogState(() => selectedAsset = v ?? assetList.first),
              ),
              DropdownButtonFormField<Party?>(
                initialValue: selectedCrew,
                decoration: InputDecoration(labelText: '$_crewLabel (optional)'),
                items: [
                  const DropdownMenuItem<Party?>(value: null, child: Text('—')),
                  ...crew.map((c) => DropdownMenuItem<Party?>(value: c, child: Text(c.name))),
                ],
                onChanged: (v) => setDialogState(() => selectedCrew = v),
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
      tripType: widget.tripType,
      assetUuid: selectedAsset.uuid,
      captainUuid: selectedCrew?.uuid,
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
                    final asset = _assetsByUuid[trip.assetUuid];
                    return ListTile(
                      leading: Icon(_statusIcon(trip.status)),
                      title: Text(asset?.name ?? trip.assetUuid),
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
      return Icons.local_shipping;
    case TripStatus.completed:
      return Icons.check_circle_outline;
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
