import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/asset/operating_asset.dart';
import '../../core/system/providers.dart';

/// Boat/Vehicle Ledger — every JournalLine tagged with this asset as the
/// dimension, across all accounts (expenses and trip/catch revenue
/// together). See LedgerRepository.dimensionStatement(). Shared between
/// Fishery and Transport — see PHASES.md Section 6/12.
class AssetLedgerScreen extends ConsumerStatefulWidget {
  const AssetLedgerScreen({super.key, required this.asset});

  final OperatingAsset asset;

  @override
  ConsumerState<AssetLedgerScreen> createState() => _AssetLedgerScreenState();
}

class _AssetLedgerScreenState extends ConsumerState<AssetLedgerScreen> {
  List<Map<String, Object?>>? _statement;
  int? _profitRevenue;
  int? _profitExpense;

  bool get _isVehicle => widget.asset.type == OperatingAssetType.vehicle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final statement = await ledger.dimensionStatement(businessId: businessId, dimensionUuid: widget.asset.uuid);

    if (_isVehicle) {
      // Vehicle Profitability — total revenue/expense across every trip
      // this vehicle has ever run, not just what's visible in the ledger
      // list (same numbers, different framing). Fishery has no equivalent
      // per-boat report — Trip Profit already covers it per trip.
      final profitability = await ref.read(vehicleProfitabilityServiceProvider.future);
      final profit = await profitability.forAsset(widget.asset.uuid);
      if (mounted) {
        setState(() {
          _statement = statement;
          _profitRevenue = profit.revenueMinorUnits;
          _profitExpense = profit.expenseMinorUnits;
        });
      }
    } else if (mounted) {
      setState(() => _statement = statement);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.asset.name} — Ledger')),
      body: statement == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_profitRevenue != null && _profitExpense != null)
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Lifetime Revenue: ${_money(_profitRevenue!)}'),
                          Text('Lifetime Expenses: ${_money(_profitExpense!)}'),
                          Text(
                            'Profit: ${_money(_profitRevenue! - _profitExpense!)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: statement.isEmpty
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
                ),
              ],
            ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
