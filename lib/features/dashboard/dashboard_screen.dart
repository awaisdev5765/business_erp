import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int? _cashBalance;
  int? _receivables;
  int? _payables;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);

    final cash = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    final receivables = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1030');
    final payables = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '2010');

    if (mounted) {
      setState(() {
        _cashBalance = cash;
        _receivables = receivables;
        _payables = -payables; // stored as a credit balance, show as positive owed
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatCard(label: 'Cash on Hand', value: _cashBalance, color: Colors.blue),
                _StatCard(label: 'Receivables (owed to you)', value: _receivables, color: Colors.green),
                _StatCard(label: 'Payables (you owe)', value: _payables, color: Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});

  final String label;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            value == null
                ? const SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    (value! / 100).toStringAsFixed(2),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold),
                  ),
          ],
        ),
      ),
    );
  }
}
