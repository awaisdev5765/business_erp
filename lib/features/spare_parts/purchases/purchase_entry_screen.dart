import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/party/party.dart';
import '../../../core/system/providers.dart';
import '../inventory/product.dart';
import 'purchase_repository.dart';

class _CartLine {
  _CartLine(this.product, this.quantity, this.unitCostMinorUnits);
  final Product product;
  int quantity;
  int unitCostMinorUnits;
  int get totalMinorUnits => quantity * unitCostMinorUnits;
}

class PurchaseEntryScreen extends ConsumerStatefulWidget {
  const PurchaseEntryScreen({super.key});

  @override
  ConsumerState<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends ConsumerState<PurchaseEntryScreen> {
  final _searchController = TextEditingController();
  List<Product> _searchResults = [];
  final List<_CartLine> _cart = [];

  List<Party> _suppliers = [];
  Party? _selectedSupplier;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(partyRepositoryProvider.future);
    final suppliers = await repo.list(businessId: businessId, type: PartyType.supplier);
    if (mounted) setState(() => _suppliers = suppliers);
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
        _cart.add(_CartLine(product, 1, product.costPriceMinorUnits));
      }
      _searchController.clear();
      _searchResults = [];
    });
  }

  int get _total => _cart.fold(0, (sum, l) => sum + l.totalMinorUnits);

  Future<void> _submit() async {
    if (_cart.isEmpty || _selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a supplier and add at least one line')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final businessId = await ref.read(currentBusinessIdProvider.future);
      final repo = await ref.read(purchaseRepositoryProvider.future);
      await repo.create(
        businessId: businessId,
        supplierUuid: _selectedSupplier!.uuid,
        createdBy: currentUser,
        deviceId: currentDeviceId,
        lineInputs: _cart
            .map((l) => PurchaseLineInput(
                  productUuid: l.product.uuid,
                  quantity: l.quantity,
                  unitCostMinorUnits: l.unitCostMinorUnits,
                ))
            .toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase saved')));
        setState(() {
          _cart.clear();
          _selectedSupplier = null;
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
      appBar: AppBar(title: const Text('New Purchase')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<Party>(
              initialValue: _selectedSupplier,
              decoration: const InputDecoration(labelText: 'Supplier', border: OutlineInputBorder()),
              items: _suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() => _selectedSupplier = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search product...',
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
                              subtitle: Text('Cost: ${_money(p.costPriceMinorUnits)}  •  Stock: ${p.stockQuantity}'),
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
                    ? const Center(child: Text('No lines yet'))
                    : ListView.builder(
                        itemCount: _cart.length,
                        itemBuilder: (context, index) {
                          final line = _cart[index];
                          return ListTile(
                            title: Text(line.product.name),
                            subtitle: Text('${_money(line.unitCostMinorUnits)} each'),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: ${_money(_total)}', style: Theme.of(context).textTheme.headlineSmall),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Purchase'),
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
