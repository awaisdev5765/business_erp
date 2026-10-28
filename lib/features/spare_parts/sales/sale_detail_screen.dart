import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/party/party.dart';
import '../../../core/system/providers.dart';
import '../../../shared/currency/currency.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/read_only_banner.dart';
import '../inventory/product.dart';
import 'refund_repository.dart';
import 'sale.dart';

/// Full breakdown of one Sale — document number, customer, payment
/// method, every line item with product name/qty/price/tax, discount,
/// and totals — plus the entry point for refunding it (qty-wise or in
/// full, see _RefundDialog below). Previously SalesHistoryScreen only
/// showed a one-line summary card per sale with no drill-down.
class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({super.key, required this.saleUuid});

  final String saleUuid;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  Sale? _sale;
  Party? _customer;
  Map<String, Product> _productsByUuid = {};
  List<RefundableLine> _refundable = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sales = await ref.read(saleRepositoryProvider.future);
    final sale = await sales.findByUuid(widget.saleUuid);
    if (sale == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final products = await ref.read(productRepositoryProvider.future);
    final productsByUuid = <String, Product>{};
    for (final line in sale.lines) {
      final product = await products.findByUuid(line.productUuid);
      if (product != null) productsByUuid[line.productUuid] = product;
    }

    Party? customer;
    if (sale.customerUuid != null) {
      final parties = await ref.read(partyRepositoryProvider.future);
      customer = await parties.findByUuid(sale.customerUuid!);
    }

    final refunds = await ref.read(refundRepositoryProvider.future);
    final refundable = await refunds.refundableLines(widget.saleUuid);

    if (mounted) {
      setState(() {
        _sale = sale;
        _customer = customer;
        _productsByUuid = productsByUuid;
        _refundable = refundable;
        _loading = false;
      });
    }
  }

  Future<void> _openRefundDialog() async {
    final refunded = await showDialog<bool>(
      context: context,
      builder: (context) => _RefundDialog(saleUuid: widget.saleUuid, refundable: _refundable),
    );
    if (refunded == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = ref.watch(isReadOnlyProvider).value ?? false;
    final currency = ref.watch(currentCurrencyProvider).value;
    final sale = _sale;

    return Scaffold(
      appBar: AppBar(title: Text(sale?.documentNumber ?? 'Sale')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : sale == null
              ? const Center(child: Text('Sale not found'))
              : Column(
                  children: [
                    if (isReadOnly) const ReadOnlyBanner(),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        children: [
                          _HeaderCard(sale: sale, customer: _customer),
                          const SizedBox(height: AppSpacing.lg),
                          _LinesCard(sale: sale, productsByUuid: _productsByUuid, currency: currency),
                          const SizedBox(height: AppSpacing.lg),
                          _TotalsCard(sale: sale, currency: currency),
                        ],
                      ),
                    ),
                    if (!isReadOnly && _canRefund(sale))
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openRefundDialog,
                            icon: const Icon(Icons.undo_outlined),
                            label: const Text('Refund'),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  bool _canRefund(Sale sale) {
    if (sale.status != SaleStatus.posted && sale.status != SaleStatus.partiallyReturned) return false;
    return _refundable.any((r) => r.refundableQty > 0);
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.sale, required this.customer});

  final Sale sale;
  final Party? customer;

  @override
  Widget build(BuildContext context) {
    final (label, color) = statusInfo(sale.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sale.documentNumber, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Chip(label: Text(label), backgroundColor: color.withValues(alpha: 0.1), side: BorderSide.none),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _row('Date', _formatDate(sale.date)),
            _row('Customer', customer?.name ?? 'Walk-in'),
            _row('Payment Method', sale.paymentMethod == PaymentMethod.cash ? 'Cash' : 'Credit'),
            _row('Created By', sale.createdBy),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.sale, required this.productsByUuid, required this.currency});

  final Sale sale;
  final Map<String, Product> productsByUuid;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Line Items', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.4),
              },
              children: [
                TableRow(
                  children: [
                    _headerCell('Product'),
                    _headerCell('Qty'),
                    _headerCell('Unit Price'),
                    _headerCell('Line Total'),
                  ],
                ),
                for (final line in sale.lines)
                  TableRow(
                    children: [
                      _cell(productsByUuid[line.productUuid]?.name ?? line.productUuid),
                      _cell('${line.quantity}'),
                      _cell(formatMoney(line.unitPriceMinorUnits, currency)),
                      _cell(formatMoney(line.lineTotalMinorUnits + line.lineTaxMinorUnits, currency)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _cell(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(text),
      );
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.sale, required this.currency});

  final Sale sale;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Subtotal', formatMoney(sale.totalMinorUnits, currency)),
            if (sale.totalTaxMinorUnits > 0) _row('Tax', formatMoney(sale.totalTaxMinorUnits, currency)),
            if (sale.discountMinorUnits > 0) _row('Discount', '-${formatMoney(sale.discountMinorUnits, currency)}'),
            const Divider(),
            _row('Net Amount Due', formatMoney(sale.netAmountDueMinorUnits, currency), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );
}

/// Lets the user pick a quantity to refund per line (capped at what's
/// left), or hit "Full Refund" to max every stepper out in one tap —
/// both paths end up calling RefundRepository.refund() with the same
/// shape of input, just with different quantities.
class _RefundDialog extends ConsumerStatefulWidget {
  const _RefundDialog({required this.saleUuid, required this.refundable});

  final String saleUuid;
  final List<RefundableLine> refundable;

  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  late Map<int, int> _quantities;
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantities = {
      for (final r in widget.refundable)
        if (r.line.id != null) r.line.id!: 0,
    };
  }

  void _fillFullRefund() {
    setState(() {
      for (final r in widget.refundable) {
        if (r.line.id != null) _quantities[r.line.id!] = r.refundableQty;
      }
    });
  }

  Future<void> _submit() async {
    final inputs = _quantities.entries
        .where((e) => e.value > 0)
        .map((e) => RefundLineInput(saleLineId: e.key, quantity: e.value))
        .toList();
    if (inputs.isEmpty) {
      setState(() => _error = 'Pick a quantity to refund on at least one line');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final refunds = await ref.read(refundRepositoryProvider.future);
      await refunds.refund(
        saleUuid: widget.saleUuid,
        lines: inputs,
        reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
        refundedBy: currentUser,
        deviceId: currentDeviceId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = '$e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currentCurrencyProvider).value;
    return AlertDialog(
      title: const Text('Refund Sale'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in widget.refundable.where((r) => r.refundableQty > 0))
                _LineStepper(
                  refundable: r,
                  currency: currency,
                  quantity: _quantities[r.line.id] ?? 0,
                  onChanged: (qty) => setState(() => _quantities[r.line.id!] = qty),
                ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _fillFullRefund,
                icon: const Icon(Icons.restore_outlined, size: 18),
                label: const Text('Full Refund (max every line)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.destructive)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Refund'),
        ),
      ],
    );
  }
}

class _LineStepper extends StatelessWidget {
  const _LineStepper({
    required this.refundable,
    required this.currency,
    required this.quantity,
    required this.onChanged,
  });

  final RefundableLine refundable;
  final String? currency;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${formatMoney(refundable.line.unitPriceMinorUnits, currency)} each — '
              '${refundable.refundableQty} of ${refundable.line.quantity} left',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: quantity > 0 ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(width: 28, child: Text('$quantity', textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: quantity < refundable.refundableQty ? () => onChanged(quantity + 1) : null,
          ),
        ],
      ),
    );
  }
}

(String, Color) statusInfo(SaleStatus status) {
  switch (status) {
    case SaleStatus.posted:
      return ('Posted', AppColors.accent);
    case SaleStatus.pendingApproval:
      return ('Pending Approval', AppColors.warning);
    case SaleStatus.partiallyReturned:
      return ('Partially Refunded', AppColors.warning);
    case SaleStatus.returned:
      return ('Returned', AppColors.destructive);
    case SaleStatus.void_:
      return ('Void', Colors.grey);
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
    '  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
