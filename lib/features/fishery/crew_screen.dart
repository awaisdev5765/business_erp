import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';

/// Captains and Crew, both stored as [Party] records (type captain/crew) —
/// see PHASES.md Section 6/12 for why Party is reused here instead of a
/// new table. No ledger/payment actions here (unlike the Customer/Supplier
/// list screen) — salary tracking is Payroll, a later phase.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key});

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
    final captains = await repo.list(businessId: businessId, type: PartyType.captain);
    final crew = await repo.list(businessId: businessId, type: PartyType.crew);
    if (mounted) setState(() => _people = [...captains, ...crew]);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    var type = PartyType.captain;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Crew Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PartyType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: PartyType.captain, child: Text('Captain')),
                  DropdownMenuItem(value: PartyType.crew, child: Text('Crew')),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? PartyType.captain),
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
      appBar: AppBar(title: const Text('Captains & Crew')),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: people == null
          ? const Center(child: CircularProgressIndicator())
          : people.isEmpty
              ? const Center(child: Text('No crew yet — tap + to add one.'))
              : ListView.builder(
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];
                    return ListTile(
                      leading: Icon(person.type == PartyType.captain ? Icons.military_tech : Icons.groups),
                      title: Text(person.name),
                      subtitle: Text('${person.type == PartyType.captain ? 'Captain' : 'Crew'}${person.phone != null ? ' • ${person.phone}' : ''}'),
                    );
                  },
                ),
    );
  }
}
