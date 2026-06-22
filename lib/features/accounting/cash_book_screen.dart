import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';

/// Cash Book: every JournalLine posted to the Cash on Hand account
/// (1010), chronological with a running balance — same pattern as the
/// Customer/Supplier Ledger, just filtered by account instead of party.
/// See PHASES.md Section 11.
class CashBookScreen extends ConsumerStatefulWidget {
  const CashBookScreen({super.key});

  @override
  ConsumerState<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends ConsumerState<CashBookScreen> {
  static const _cashAccountCode = '1010';
  List<Map<String, Object?>>? _statement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);
    final statement = await ledger.accountStatement(businessId: businessId, accountCode: _cashAccountCode);
    if (mounted) setState(() => _statement = statement);
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    var runningBalance = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Book')),
      body: statement == null
          ? const Center(child: CircularProgressIndicator())
          : statement.isEmpty
              ? const Center(child: Text('No cash transactions yet'))
              : ListView.builder(
                  itemCount: statement.length,
                  itemBuilder: (context, index) {
                    final row = statement[index];
                    final debit = row['debit_minor_units'] as int;
                    final credit = row['credit_minor_units'] as int;
                    runningBalance += debit - credit;
                    final date = DateTime.parse(row['date'] as String);

                    return ListTile(
                      title: Text('${row['source_type']} — ${row['description'] ?? row['source_id']}'),
                      subtitle: Text(
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  •  ${row['status']}',
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (debit > 0) Text('In ${_money(debit)}', style: const TextStyle(color: Colors.green)),
                          if (credit > 0) Text('Out ${_money(credit)}', style: const TextStyle(color: Colors.red)),
                          Text('Bal: ${_money(runningBalance)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
