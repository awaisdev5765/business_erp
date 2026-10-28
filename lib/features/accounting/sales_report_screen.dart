import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/account.dart';
import '../../core/system/providers.dart';
import '../../shared/currency/currency.dart';
import '../../shared/pdf/report_pdf.dart';
import '../../shared/theme/app_theme.dart';
import '../spare_parts/sales/sale.dart';

/// Daily Report and Month-End Report are the same shape over a different
/// date range, so one screen covers both rather than duplicating it —
/// "today" with prev/next-day arrows, or "this month" with prev/next-
/// month arrows. Combines a sales/refunds summary (SaleRepository /
/// RefundRepository) with the existing Income/Expense breakdown
/// (LedgerRepository.trialBalanceForRange, same query ProfitAndLossScreen
/// already uses) so an owner gets both halves of "how did today/this
/// month go" in one place.
enum SalesReportPeriod { daily, monthly }

class SalesReportScreen extends ConsumerStatefulWidget {
  const SalesReportScreen({super.key, required this.period});

  final SalesReportPeriod period;

  @override
  ConsumerState<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends ConsumerState<SalesReportScreen> {
  DateTime _anchor = DateTime.now();
  bool _loading = true;

  int _salesCount = 0;
  int _grossSales = 0;
  int _discounts = 0;
  int _tax = 0;
  int _cashSales = 0;
  int _creditSales = 0;
  int _refundsCount = 0;
  int _refundsTotal = 0;
  int _totalIncome = 0;
  int _totalExpense = 0;

  (DateTime, DateTime) get _range {
    if (widget.period == SalesReportPeriod.daily) {
      final from = DateTime(_anchor.year, _anchor.month, _anchor.day);
      final to = from.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      return (from, to);
    }
    final from = DateTime(_anchor.year, _anchor.month, 1);
    final to = DateTime(_anchor.year, _anchor.month + 1, 1).subtract(const Duration(milliseconds: 1));
    return (from, to);
  }

  String get _periodLabel {
    if (widget.period == SalesReportPeriod.daily) {
      return '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}-${_anchor.day.toString().padLeft(2, '0')}';
    }
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[_anchor.month - 1]} ${_anchor.year}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _shift(int amount) {
    setState(() {
      _anchor = widget.period == SalesReportPeriod.daily
          ? _anchor.add(Duration(days: amount))
          : DateTime(_anchor.year, _anchor.month + amount, 1);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _range;
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final sales = await ref.read(saleRepositoryProvider.future);
    final refunds = await ref.read(refundRepositoryProvider.future);
    final ledger = await ref.read(ledgerRepositoryProvider.future);

    final salesInRange = await sales.listForDateRange(businessId: businessId, from: from, to: to);
    // pendingApproval sales haven't posted a JournalEntry or moved stock
    // yet — they're not "today's business" until approved, so they're
    // excluded from every total below, same way Approvals/Dashboard treat
    // them.
    final countedSales = salesInRange.where((s) => s.status != SaleStatus.pendingApproval).toList();

    final refundsInRange = await refunds.listForDateRange(businessId: businessId, from: from, to: to);
    final ledgerRows = await ledger.trialBalanceForRange(businessId: businessId, from: from, to: to);

    final incomeRows = ledgerRows.where((r) => r['type'] == AccountType.income.name);
    final expenseRows = ledgerRows.where((r) => r['type'] == AccountType.expense.name);
    final totalIncome = incomeRows.fold<int>(0, (sum, r) => sum + (r['total_credit'] as int) - (r['total_debit'] as int));
    final totalExpense = expenseRows.fold<int>(0, (sum, r) => sum + (r['total_debit'] as int) - (r['total_credit'] as int));

    if (mounted) {
      setState(() {
        _salesCount = countedSales.length;
        _grossSales = countedSales.fold(0, (sum, s) => sum + s.totalMinorUnits);
        _discounts = countedSales.fold(0, (sum, s) => sum + s.discountMinorUnits);
        _tax = countedSales.fold(0, (sum, s) => sum + s.totalTaxMinorUnits);
        _cashSales = countedSales.where((s) => s.paymentMethod == PaymentMethod.cash).fold(0, (sum, s) => sum + s.netAmountDueMinorUnits);
        _creditSales = countedSales.where((s) => s.paymentMethod == PaymentMethod.credit).fold(0, (sum, s) => sum + s.netAmountDueMinorUnits);
        _refundsCount = refundsInRange.length;
        _refundsTotal = refundsInRange.fold(0, (sum, r) => sum + r.netAmountMinorUnits);
        _totalIncome = totalIncome;
        _totalExpense = totalExpense;
        _loading = false;
      });
    }
  }

  int get _netSales => _grossSales + _tax - _discounts;
  int get _netRevenue => _netSales - _refundsTotal;

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currentCurrencyProvider).value;
    final title = widget.period == SalesReportPeriod.daily ? 'Daily Report' : 'Month-End Report';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Export PDF',
            onPressed: _loading
                ? null
                : () async {
                    final business = await ref.read(currentBusinessProvider.future);
                    await ReportPdf.printSalesReport(
                      businessName: business.name,
                      periodLabel: _periodLabel,
                      salesCount: _salesCount,
                      grossSales: _grossSales,
                      discounts: _discounts,
                      tax: _tax,
                      netSales: _netSales,
                      refundsCount: _refundsCount,
                      refundsTotal: _refundsTotal,
                      netRevenue: _netRevenue,
                      cashSales: _cashSales,
                      creditSales: _creditSales,
                      totalIncome: _totalIncome,
                      totalExpense: _totalExpense,
                    );
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                    Text(_periodLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.payments_outlined, color: AppColors.success, size: 24),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        const Text('Net Revenue', style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          formatMoney(_netRevenue, currency),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _SummaryCard(
                  title: 'Sales Summary',
                  rows: [
                    ('Sales Count', '$_salesCount'),
                    ('Gross Sales', formatMoney(_grossSales, currency)),
                    ('Discounts Given', formatMoney(_discounts, currency)),
                    ('Tax Collected', formatMoney(_tax, currency)),
                    ('Net Sales', formatMoney(_netSales, currency)),
                    ('Cash Sales', formatMoney(_cashSales, currency)),
                    ('Credit Sales', formatMoney(_creditSales, currency)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SummaryCard(
                  title: 'Refunds',
                  rows: [
                    ('Refunds Count', '$_refundsCount'),
                    ('Refunds Total', formatMoney(_refundsTotal, currency)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SummaryCard(
                  title: 'Financial Summary',
                  rows: [
                    ('Total Income', formatMoney(_totalIncome, currency)),
                    ('Total Expense', formatMoney(_totalExpense, currency)),
                    ('Net Profit', formatMoney(_totalIncome - _totalExpense, currency)),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(r.$1), Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600))],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
