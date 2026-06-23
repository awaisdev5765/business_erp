import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';

/// A registry of [Party] records for one or more crew-like roles —
/// Captains+Crew for Fishery, Drivers for Transport. Same model
/// (PHASES.md Section 6/12), no ledger/payment actions (salary tracking
/// is a later Payroll phase). [onTapPerson] is optional — Transport uses
/// it to drill into Driver Performance; Fishery doesn't need a per-person
/// drill-down screen.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({
    super.key,
    required this.title,
    required this.roles,
    required this.roleLabels,
    this.onTapPerson,
  });

  final String title;
  final List<PartyType> roles;
  final Map<PartyType, String> roleLabels;
  final void Function(BuildContext context, Party person)? onTapPerson;

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  List<Party>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    final people = <Party>[];
    for (final role in widget.roles) {
      people.addAll(await repo.list(businessId: businessId, type: role));
    }
    if (mounted) setState(() => _people = people);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    var type = widget.roles.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('New ${widget.title.split(' ').first}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.roles.length > 1)
                DropdownButtonFormField<PartyType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: widget.roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(widget.roleLabels[r]!)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => type = v ?? widget.roles.first),
                ),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true || nameController.text.isEmpty) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      type: type,
      name: nameController.text,
      phone: phoneController.text.isEmpty ? null : phoneController.text,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: people == null
          ? const Center(child: CircularProgressIndicator())
          : people.isEmpty
              ? const Center(child: Text('No one yet — tap + to add one.'))
              : ListView.builder(
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(person.name),
                      subtitle: Text(
                        '${widget.roleLabels[person.type] ?? person.type.name}${person.phone != null ? ' • ${person.phone}' : ''}',
                      ),
                      trailing: widget.onTapPerson != null ? const Icon(Icons.chevron_right) : null,
                      onTap: widget.onTapPerson != null ? () => widget.onTapPerson!(context, person) : null,
                    );
                  },
                ),
    );
  }
}
