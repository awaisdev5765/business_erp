import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/system/providers.dart';

/// Boat Ledger — every JournalLine tagged with this boat as the
/// dimension, across all accounts (fuel, ice, food, maintenance expenses
/// and catch revenue together). See LedgerRepository.dimensionStatement().
class BoatLedgerScreen extends ConsumerStatefulWidget {
  const BoatLedgerScreen({super.key, required this.boat});

  final OperatingAsset boat;

  @override
  ConsumerState<BoatLedgerScreen> createState() => _BoatLedgerScreenState();
}

class _BoatLedgerScreenState extends ConsumerState<BoatLedgerScreen> {
  List<Map<String, Object?>>? _statement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final statement = await ledger.dimensionStatement(businessId: businessId, dimensionUuid: widget.boat.uuid);
    if (mounted) setState(() => _statement = statement);
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.boat.name} — Ledger')),
      body: statement == null
          ? const Center(child: CircularProgressIndicator())
          : statement.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : ListView.builder(
                  itemCount: statement.length,
                  itemBuilder: (context, index) {
                    final row = statement[index];
                    final debit = row['debit_minor_units'] as int;
                    final credit = row['credit_minor_units'] as int;
                    final date = DateTime.parse(row['date'] as String);

                    return ListTile(
                      title: Text('${row['account_code']} — ${row['source_type']}'),
                      subtitle: Text('${row['description'] ?? row['source_id']}  •  ${_formatDate(date)}'),
                      trailing: debit > 0
                          ? Text('Dr ${_money(debit)}', style: const TextStyle(color: Colors.red))
                          : Text('Cr ${_money(credit)}', style: const TextStyle(color: Colors.green)),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
