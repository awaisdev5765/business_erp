import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/system/providers.dart';
import 'product.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  List<Product>? _products;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(productRepositoryProvider.future);
    final products = await repo.list(businessId: businessId);
    if (mounted) setState(() => _products = products);
  }

  Future<void> _showAddDialog() async {
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final costController = TextEditingController();
    final priceController = TextEditingController();
    final stockController = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Product'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: skuController, decoration: const InputDecoration(labelText: 'SKU')),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                controller: costController,
                decoration: const InputDecoration(labelText: 'Cost price'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Sale price'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: stockController,
                decoration: const InputDecoration(labelText: 'Opening stock'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    if (skuController.text.isEmpty || nameController.text.isEmpty) return;

    final businessId = await ref.read(currentBusinessIdProvider.future);
    final repo = await ref.read(productRepositoryProvider.future);
    await repo.create(
      businessId: businessId,
      sku: skuController.text,
      name: nameController.text,
      costPriceMinorUnits: ((double.tryParse(costController.text) ?? 0) * 100).round(),
      salePriceMinorUnits: ((double.tryParse(priceController.text) ?? 0) * 100).round(),
      openingStock: int.tryParse(stockController.text) ?? 0,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'New Product',
        child: const Icon(Icons.add),
      ),
      body: products == null
          ? const Center(child: CircularProgressIndicator())
          : products.isEmpty
              ? const Center(child: Text('No products yet — tap + to add one.'))
              : ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final p = products[index];
                    final low = p.stockQuantity <= p.reorderLevel;
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text('SKU: ${p.sku}  •  Cost: ${_money(p.costPriceMinorUnits)}  •  Price: ${_money(p.salePriceMinorUnits)}'),
                      trailing: Text(
                        'Stock: ${p.stockQuantity}',
                        style: TextStyle(
                          color: low ? Colors.red : null,
                          fontWeight: low ? FontWeight.bold : null,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
