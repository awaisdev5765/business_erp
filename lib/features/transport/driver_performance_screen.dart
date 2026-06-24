import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party/party.dart';
import '../../core/system/providers.dart';
import '../../shared/theme/app_theme.dart';

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
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lifetime totals across every trip',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 700 ? 3 : 1;
                      return GridView.count(
                        crossAxisCount: columns,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: AppSpacing.lg,
                        crossAxisSpacing: AppSpacing.lg,
                        childAspectRatio: 2.4,
                        children: [
                          _StatCard(label: 'Revenue Earned', value: revenue, icon: Icons.trending_up, color: AppColors.success),
                          _StatCard(label: 'Expenses Incurred', value: expense, icon: Icons.trending_down, color: AppColors.warning),
                          _StatCard(
                            label: 'Net',
                            value: revenue - expense,
                            icon: Icons.account_balance_wallet_outlined,
                            color: revenue - expense >= 0 ? AppColors.success : AppColors.destructive,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _money(value),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
