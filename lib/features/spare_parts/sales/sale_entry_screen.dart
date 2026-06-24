import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/party/party.dart';
import '../../../core/system/providers.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/quantity_stepper.dart';
import '../inventory/product.dart';
import 'invoice_pdf.dart';
import 'sale.dart';
import 'sale_repository.dart';

class _CartLine {
  _CartLine(this.product, this.quantity);
  final Product product;
  int quantity;
  int get totalMinorUnits => quantity * product.salePriceMinorUnits;
}

/// POS-style two-pane layout: product search + cart on the left, a
/// sticky checkout summary on the right — replaces the original single
/// stacked-column form, which buried the total/submit button below a
/// variable-height cart list.
class SaleEntryScreen extends ConsumerStatefulWidget {
  const SaleEntryScreen({super.key});

  @override
  ConsumerState<SaleEntryScreen> createState() => _SaleEntryScreenState();
}

class _SaleEntryScreenState extends ConsumerState<SaleEntryScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Product> _searchResults = [];
  final List<_CartLine> _cart = [];

  PaymentMethod _paymentMethod = PaymentMethod.cash;
  List<Party> _customers = [];
  Party? _selectedCustomer;
  bool _submitting = false;
  String _businessName = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    final business = await ref.read(currentBusinessProvider.future);
    final customers = await repo.list(businessId: businessId, type: PartyType.customer);
    if (mounted) {
      setState(() {
        _customers = customers;
        _businessName = business.name;
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(productRepositoryProvider.future);
    final results = await repo.search(businessId: businessId, query: query);
    if (mounted) setState(() => _searchResults = results);
  }

  void _addToCart(Product product) {
    setState(() {
      final existingIndex = _cart.indexWhere((l) => l.product.uuid == product.uuid);
      if (existingIndex != -1) {
        _cart[existingIndex].quantity++;
      } else {
        _cart.add(_CartLine(product, 1));
      }
      _searchController.clear();
      _searchResults = [];
    });
    _searchFocusNode.requestFocus();
  }

  int get _total => _cart.fold(0, (sum, l) => sum + l.totalMinorUnits);
  int get _itemCount => _cart.fold(0, (sum, l) => sum + l.quantity);

  Future<void> _submit() async {
    if (_cart.isEmpty) return;
    if (_paymentMethod == PaymentMethod.credit && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer for a credit sale')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final businessId = await ref.read(currentBusinessIdProvider.future);
      final repo = await ref.read(saleRepositoryProvider.future);
      final sale = await repo.create(
        businessId: businessId,
        customerUuid: _selectedCustomer?.uuid,
        paymentMethod: _paymentMethod,
        createdBy: currentUser,
        deviceId: currentDeviceId,
        lineInputs: _cart
            .map((l) => SaleLineInput(
                  productUuid: l.product.uuid,
                  quantity: l.quantity,
                  unitPriceMinorUnits: l.product.salePriceMinorUnits,
                ))
            .toList(),
      );

      final productsByUuid = {for (final l in _cart) l.product.uuid: l.product};
      final savedCustomer = _selectedCustomer;
      final businessName = _businessName;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Sale saved'),
          action: SnackBarAction(
            label: 'PRINT INVOICE',
            onPressed: () => InvoicePdf.printInvoice(
              sale: sale,
              businessName: businessName,
              customer: savedCustomer,
              productsByUuid: productsByUuid,
            ),
          ),
        ));
        setState(() {
          _cart.clear();
          _selectedCustomer = null;
          _paymentMethod = PaymentMethod.cash;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Sale')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: _buildCartPane(context)),
          Container(width: 1, color: Theme.of(context).dividerColor),
          SizedBox(width: 340, child: _buildCheckoutPane(context)),
        ],
      ),
    );
  }

  Widget _buildCartPane(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Scan or search product...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _search,
              ),
              if (_searchResults.isNotEmpty)
                Positioned(
                  top: 58,
                  left: 0,
                  right: 0,
                  child: Card(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = _searchResults[index];
                          final lowStock = p.stockQuantity <= 5;
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(_money(p.salePriceMinorUnits)),
                            trailing: Chip(
                              label: Text('Stock: ${p.stockQuantity}'),
                              backgroundColor: lowStock ? AppColors.destructive.withValues(alpha: 0.12) : null,
                              labelStyle: lowStock ? const TextStyle(color: AppColors.destructive) : null,
                              side: BorderSide.none,
                            ),
                            onTap: () => _addToCart(p),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: AppSpacing.md),
                        Text('Search a product above to start the sale', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final line = _cart[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      '${_money(line.product.salePriceMinorUnits)} each',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              QuantityStepper(
                                quantity: line.quantity,
                                onDecrement: () => setState(() {
                                  line.quantity--;
                                  if (line.quantity <= 0) _cart.removeAt(index);
                                }),
                                onIncrement: () => setState(() => line.quantity++),
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  _money(line.totalMinorUnits),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutPane(BuildContext context) {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : AppColors.background,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Order Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: PaymentMethod.values.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
            onChanged: (v) => setState(() => _paymentMethod = v ?? PaymentMethod.cash),
          ),
          if (_paymentMethod == PaymentMethod.credit) ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<Party>(
              initialValue: _selectedCustomer,
              decoration: const InputDecoration(labelText: 'Customer'),
              items: _customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _selectedCustomer = v),
            ),
          ],
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items', style: TextStyle(color: Colors.grey.shade600)),
              Text('$_itemCount'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(
                _money(_total),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: (_submitting || _cart.isEmpty) ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg)),
            child: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Complete Sale (F3)'),
          ),
        ],
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
