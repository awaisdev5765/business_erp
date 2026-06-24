import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/system/providers.dart';
import '../../../shared/currency/currency.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/read_only_banner.dart';
import 'sale.dart';

/// Every Sale for the active business, newest first — the entry point
/// for returns (SaleRepository.returnSale()), since there was
/// previously no way to even look up a past sale from the UI (New Sale
/// only ever built new ones).
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

  Future<void> _confirmReturn(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return Sale?'),
        content: Text(
          'This returns every line on ${sale.documentNumber} — stock goes back, and the original '
          "journal entry is reversed. There's no undo for this from the app.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Return'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = await ref.read(saleRepositoryProvider.future);
    try {
      await repo.returnSale(sale.uuid, returnedBy: currentUser, deviceId: currentDeviceId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${sale.documentNumber} returned')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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
                          final (label, color) = _statusInfo(sale.status);
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.receipt_long_outlined, color: color, size: 18),
                              ),
                              title: Text(sale.documentNumber),
                              subtitle: Text('${_formatDate(sale.date)}  •  ${formatMoney(sale.grandTotalMinorUnits, currency)}'),
                              trailing: sale.status == SaleStatus.posted
                                  ? OutlinedButton(
                                      onPressed: isReadOnly ? null : () => _confirmReturn(sale),
                                      child: const Text('Return'),
                                    )
                                  : Chip(label: Text(label), backgroundColor: color.withValues(alpha: 0.1), side: BorderSide.none),
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

(String, Color) _statusInfo(SaleStatus status) {
  switch (status) {
    case SaleStatus.posted:
      return ('Posted', AppColors.accent);
    case SaleStatus.pendingApproval:
      return ('Pending Approval', AppColors.warning);
    case SaleStatus.returned:
      return ('Returned', AppColors.destructive);
    case SaleStatus.void_:
      return ('Void', Colors.grey);
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
