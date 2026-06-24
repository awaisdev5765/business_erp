import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/system/providers.dart';
import '../../../shared/theme/app_theme.dart';
import 'product.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  List<Product>? _products;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: 'SKU'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: costController,
                decoration: const InputDecoration(labelText: 'Cost price'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Sale price'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: stockController,
                decoration: const InputDecoration(labelText: 'Opening stock'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
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
      costPriceMinorUnits: ((double.tryParse(costController.text) ?? 0) * 100)
          .round(),
      salePriceMinorUnits: ((double.tryParse(priceController.text) ?? 0) * 100)
          .round(),
      openingStock: int.tryParse(stockController.text) ?? 0,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final filtered = products == null
        ? null
        : (_query.isEmpty
              ? products
              : products
                    .where(
                      (p) =>
                          p.name.toLowerCase().contains(_query) ||
                          p.sku.toLowerCase().contains(_query),
                    )
                    .toList());

    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'New Product',
        child: const Icon(Icons.add),
      ),
      body: products == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (products.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or SKU...',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                Expanded(
                  child: products.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Text('No products yet — tap + to add one.'),
                            ],
                          ),
                        )
                      : filtered!.isEmpty
                      ? Center(
                          child: Text(
                            'No matches for "$_query"',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final p = filtered[index];
                            final low = p.stockQuantity <= p.reorderLevel;
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                  vertical: AppSpacing.xs,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: AppColors.accent,
                                    size: 18,
                                  ),
                                ),
                                title: Text(p.name),
                                subtitle: Text(
                                  'SKU: ${p.sku}  •  Cost: ${_money(p.costPriceMinorUnits)}  •  Price: ${_money(p.salePriceMinorUnits)}',
                                ),
                                trailing: Chip(
                                  label: Text('Stock: ${p.stockQuantity}'),
                                  backgroundColor: low
                                      ? AppColors.destructive.withValues(
                                          alpha: 0.12,
                                        )
                                      : null,
                                  labelStyle: TextStyle(
                                    color: low ? AppColors.destructive : null,
                                    fontWeight: low ? FontWeight.w700 : null,
                                  ),
                                  side: BorderSide.none,
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
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
