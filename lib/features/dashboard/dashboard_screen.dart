import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/system/providers.dart';
import '../../shared/currency/currency.dart';
import '../../shared/theme/app_theme.dart';

/// Income account codes shared across all three verticals — see
/// chart_of_accounts_seed.dart. Summed together for the revenue trend
/// chart since the Dashboard is generic across business types (Sales
/// Income, Trip/Catch Income, Other Income all count as "revenue" here).
const _incomeAccountCodes = ['4010', '4020', '4030'];

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int? _cashBalance;
  int? _receivables;
  int? _payables;
  String? _businessName;
  String? _currency;
  List<int>? _dailyRevenueLast14Days; // index 0 = 13 days ago, index 13 = today

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final business = await ref.read(currentBusinessProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);

    final cash = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1010');
    final receivables = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '1030');
    final payables = await ledger.accountBalanceMinorUnits(businessId: businessId, accountCode: '2010');

    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final dailyRevenue = List<int>.filled(14, 0);

    for (final code in _incomeAccountCodes) {
      final statement = await ledger.accountStatement(businessId: businessId, accountCode: code);
      for (final row in statement) {
        final date = DateTime.parse(row['date'] as String);
        final day = DateTime(date.year, date.month, date.day);
        final daysAgo = startOfToday.difference(day).inDays;
        if (daysAgo < 0 || daysAgo > 13) continue;
        final amount = (row['credit_minor_units'] as int) - (row['debit_minor_units'] as int);
        dailyRevenue[13 - daysAgo] += amount;
      }
    }

    if (mounted) {
      setState(() {
        _cashBalance = cash;
        _receivables = receivables;
        _payables = -payables; // stored as a credit balance, show as positive owed
        _businessName = business.name;
        _currency = business.baseCurrency;
        _dailyRevenueLast14Days = dailyRevenue;
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
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              _businessName == null ? 'Overview' : 'Overview — $_businessName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Here's where things stand right now.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.lg,
                  crossAxisSpacing: AppSpacing.lg,
                  childAspectRatio: 2.4,
                  children: [
                    _StatCard(
                      label: 'Cash on Hand',
                      value: _cashBalance,
                      currency: _currency,
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppColors.accent,
                    ),
                    _StatCard(
                      label: 'Receivables (owed to you)',
                      value: _receivables,
                      currency: _currency,
                      icon: Icons.call_received_outlined,
                      color: AppColors.success,
                    ),
                    _StatCard(
                      label: 'Payables (you owe)',
                      value: _payables,
                      currency: _currency,
                      icon: Icons.call_made_outlined,
                      color: AppColors.warning,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            _RevenueTrendCard(dailyRevenue: _dailyRevenueLast14Days, currency: _currency),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.currency, required this.icon, required this.color});

  final String label;
  final int? value;
  final String? currency;
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
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  value == null
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          formatMoney(value!, currency),
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

/// Revenue (all income accounts combined) for each of the last 14 days
/// — the one trend chart the "Data-Dense Dashboard" style calls for that
/// this app's KPI-cards-only Dashboard never had.
class _RevenueTrendCard extends StatelessWidget {
  const _RevenueTrendCard({required this.dailyRevenue, this.currency});

  final List<int>? dailyRevenue;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final data = dailyRevenue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Revenue — Last 14 Days', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 180,
              child: data == null
                  ? const Center(child: CircularProgressIndicator())
                  : data.every((v) => v == 0)
                      ? Center(child: Text('No revenue posted in the last 14 days', style: TextStyle(color: Colors.grey.shade600)))
                      : _buildChart(context, data, currency),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<int> data, String? currency) {
    final maxValue = data.reduce((a, b) => a > b ? a : b).toDouble();
    final today = DateTime.now();

    return BarChart(
      BarChartData(
        maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final daysAgo = 13 - value.toInt();
                final date = today.subtract(Duration(days: daysAgo));
                // Label every other day to avoid crowding.
                if (value.toInt() % 2 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text('${date.day}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(formatMoney(rod.toY.round(), currency), const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].toDouble(),
                  color: AppColors.accent,
                  width: 14,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
