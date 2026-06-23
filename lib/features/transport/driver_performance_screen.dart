import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';

class DriverPerformanceScreen extends ConsumerStatefulWidget {
  const DriverPerformanceScreen({super.key, required this.driver});

  final Party driver;

  @override
  ConsumerState<DriverPerformanceScreen> createState() => _DriverPerformanceScreenState();
}

class _DriverPerformanceScreenState extends ConsumerState<DriverPerformanceScreen> {
  int? _revenue;
  int? _expense;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await ref.read(driverPerformanceServiceProvider.future);
    final perf = await service.forDriver(widget.driver.uuid);
    if (mounted) {
      setState(() {
        _revenue = perf.revenueMinorUnits;
        _expense = perf.expenseMinorUnits;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final revenue = _revenue;
    final expense = _expense;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.driver.name} — Performance')),
      body: revenue == null || expense == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: revenue - expense >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lifetime totals across every trip', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text('Revenue earned: ${_money(revenue)}'),
                      Text('Expenses incurred: ${_money(expense)}'),
                      const Divider(),
                      Text(
                        'Net: ${_money(revenue - expense)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
