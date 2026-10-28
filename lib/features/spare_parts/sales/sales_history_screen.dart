import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/system/providers.dart';
import '../../../shared/currency/currency.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/read_only_banner.dart';
import 'sale.dart';
import 'sale_detail_screen.dart';

/// Every Sale for the active business, newest first — tapping a row opens
/// SaleDetailScreen, which is also where refunds (qty-wise or full) now
/// happen; this list itself is read-only navigation.
class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  List<Sale>? _sales;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(saleRepositoryProvider.future);
    final sales = await repo.list(businessId: businessId);
    if (mounted) setState(() => _sales = sales);
  }

  Future<void> _openDetail(Sale sale) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SaleDetailScreen(saleUuid: sale.uuid)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sales = _sales;
    final isReadOnly = ref.watch(isReadOnlyProvider).value ?? false;
    final currency = ref.watch(currentCurrencyProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Sales History')),
      body: Column(
        children: [
          if (isReadOnly) const ReadOnlyBanner(),
          Expanded(
            child: sales == null
                ? const Center(child: CircularProgressIndicator())
                : sales.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: AppSpacing.md),
                            const Text('No sales yet'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: sales.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final sale = sales[index];
                          final (label, color) = statusInfo(sale.status);
                          return Card(
                            child: ListTile(
                              onTap: () => _openDetail(sale),
                              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.receipt_long_outlined, color: color, size: 18),
                              ),
                              title: Text(sale.documentNumber),
                              subtitle: Text('${_formatDate(sale.date)}  •  ${formatMoney(sale.grandTotalMinorUnits, currency)}'),
                              trailing: Chip(label: Text(label), backgroundColor: color.withValues(alpha: 0.1), side: BorderSide.none),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
    '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
