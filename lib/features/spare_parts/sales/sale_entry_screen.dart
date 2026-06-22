import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/party/party.dart';
import '../../../core/system/providers.dart';
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

class SaleEntryScreen extends ConsumerStatefulWidget {
  const SaleEntryScreen({super.key});

  @override
  ConsumerState<SaleEntryScreen> createState() => _SaleEntryScreenState();
}

class _SaleEntryScreenState extends ConsumerState<SaleEntryScreen> {
  final _searchController = TextEditingController();
  List<Product> _searchResults = [];
  final List<_CartLine> _cart = [];

  PaymentMethod _paymentMethod = PaymentMethod.cash;
  List<Party> _customers = [];
  Party? _selectedCustomer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    final customers = await repo.list(businessId: businessId, type: PartyType.customer);
    if (mounted) setState(() => _customers = customers);
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
  }

  int get _total => _cart.fold(0, (sum, l) => sum + l.totalMinorUnits);

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Sale saved'),
          action: SnackBarAction(
            label: 'PRINT INVOICE',
            onPressed: () => InvoicePdf.printInvoice(
              sale: sale,
              businessName: 'My Spare Parts Shop',
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Scan/search product...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            if (_searchResults.isNotEmpty)
              Card(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView(
                    shrinkWrap: true,
                    children: _searchResults
                        .map((p) => ListTile(
                              title: Text(p.name),
                              subtitle: Text('${_money(p.salePriceMinorUnits)}  •  Stock: ${p.stockQuantity}'),
                              onTap: () => _addToCart(p),
                            ))
                        .toList(),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: _cart.isEmpty
                    ? const Center(child: Text('Cart is empty'))
                    : ListView.builder(
                        itemCount: _cart.length,
                        itemBuilder: (context, index) {
                          final line = _cart[index];
                          return ListTile(
                            title: Text(line.product.name),
                            subtitle: Text('${_money(line.product.salePriceMinorUnits)} each'),
                            leading: SizedBox(
                              width: 72,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove),
                                    onPressed: () => setState(() {
                                      line.quantity--;
                                      if (line.quantity <= 0) _cart.removeAt(index);
                                    }),
                                  ),
                                  Text('${line.quantity}'),
                                ],
                              ),
                            ),
                            trailing: Text(_money(line.totalMinorUnits)),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<PaymentMethod>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment', border: OutlineInputBorder()),
                    items: PaymentMethod.values
                        .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _paymentMethod = v ?? PaymentMethod.cash),
                  ),
                ),
                const SizedBox(width: 12),
                if (_paymentMethod == PaymentMethod.credit)
                  Expanded(
                    child: DropdownButtonFormField<Party>(
                      initialValue: _selectedCustomer,
                      decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
                      items: _customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                      onChanged: (v) => setState(() => _selectedCustomer = v),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: ${_money(_total)}', style: Theme.of(context).textTheme.headlineSmall),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Sale (F3)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
