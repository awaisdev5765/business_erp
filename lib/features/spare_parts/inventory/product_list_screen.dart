import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/system/providers.dart';
import '../../../shared/theme/app_theme.dart';
import 'category.dart';
import 'product.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  List<Product>? _products;
  Map<String, Category> _categoriesByUuid = {};
  Map<String, Brand> _brandsByUuid = {};
  String? _categoryFilter; // null = all categories
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
    final categoryRepo = await ref.read(categoryRepositoryProvider.future);
    final brandRepo = await ref.read(brandRepositoryProvider.future);
    final products = await repo.list(businessId: businessId);
    final categories = await categoryRepo.list(businessId: businessId);
    final brands = await brandRepo.list(businessId: businessId);
    if (mounted) {
      setState(() {
        _products = products;
        _categoriesByUuid = {for (final c in categories) c.uuid: c};
        _brandsByUuid = {for (final b in brands) b.uuid: b};
      });
    }
  }

  /// Pick an existing category or type a new name to create one on the
  /// fly — same pattern as TripDetailScreen's fish-category picker.
  Future<Category?> _pickOrCreateCategory() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final categoryRepo = await ref.read(categoryRepositoryProvider.future);
    final categories = await categoryRepo.list(businessId: businessId);

    Category? selected;
    final newNameController = TextEditingController();

    if (!mounted) return null;
    final picked = await showDialog<Category?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (categories.isNotEmpty)
                DropdownButtonFormField<Category?>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Existing category'),
                  items: [
                    const DropdownMenuItem<Category?>(value: null, child: Text('None')),
                    ...categories.map((c) => DropdownMenuItem<Category?>(value: c, child: Text(c.name))),
                  ],
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: newNameController,
                decoration: const InputDecoration(labelText: 'Or add a new category'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (newNameController.text.isNotEmpty) {
                  final created = await categoryRepo.create(businessId: businessId, name: newNameController.text);
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                } else {
                  Navigator.pop(context, selected);
                }
              },
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );
    return picked;
  }

  /// Same pattern as [_pickOrCreateCategory] — Brand existed in the
  /// schema since Phase 1 (Product.brandUuid) right alongside Category,
  /// but only Category ever got a picker.
  Future<Brand?> _pickOrCreateBrand() async {
    final businessId = await ref.read(currentBusinessIdProvider.future);
    final brandRepo = await ref.read(brandRepositoryProvider.future);
    final brands = await brandRepo.list(businessId: businessId);

    Brand? selected;
    final newNameController = TextEditingController();

    if (!mounted) return null;
    final picked = await showDialog<Brand?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Brand'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (brands.isNotEmpty)
                DropdownButtonFormField<Brand?>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Existing brand'),
                  items: [
                    const DropdownMenuItem<Brand?>(value: null, child: Text('None')),
                    ...brands.map((b) => DropdownMenuItem<Brand?>(value: b, child: Text(b.name))),
                  ],
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: newNameController,
                decoration: const InputDecoration(labelText: 'Or add a new brand'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (newNameController.text.isNotEmpty) {
                  final created = await brandRepo.create(businessId: businessId, name: newNameController.text);
                  if (!context.mounted) return;
                  Navigator.pop(context, created);
                } else {
                  Navigator.pop(context, selected);
                }
              },
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );
    return picked;
  }

  Future<void> _showAddDialog() async {
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final costController = TextEditingController();
    final priceController = TextEditingController();
    final stockController = TextEditingController(text: '0');
    Category? category;
    Brand? brand;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickOrCreateCategory();
                    setDialogState(() => category = picked);
                  },
                  icon: const Icon(Icons.sell_outlined, size: 16),
                  label: Text(category?.name ?? 'Category (optional)'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickOrCreateBrand();
                    setDialogState(() => brand = picked);
                  },
                  icon: const Icon(Icons.local_offer_outlined, size: 16),
                  label: Text(brand?.name ?? 'Brand (optional)'),
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
      categoryUuid: category?.uuid,
      brandUuid: brand?.uuid,
      costPriceMinorUnits: ((double.tryParse(costController.text) ?? 0) * 100)
          .round(),
      salePriceMinorUnits: ((double.tryParse(priceController.text) ?? 0) * 100)
          .round(),
      openingStock: int.tryParse(stockController.text) ?? 0,
      createdBy: currentUser,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final filtered = products?.where((p) {
      final matchesQuery =
          _query.isEmpty || p.name.toLowerCase().contains(_query) || p.sku.toLowerCase().contains(_query);
      final matchesCategory = _categoryFilter == null || p.categoryUuid == _categoryFilter;
      return matchesQuery && matchesCategory;
    }).toList();

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
                if (products.isNotEmpty) ...[
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
                  if (_categoriesByUuid.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
                      child: SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.sm),
                              child: ChoiceChip(
                                label: const Text('All'),
                                selected: _categoryFilter == null,
                                onSelected: (_) => setState(() => _categoryFilter = null),
                              ),
                            ),
                            ..._categoriesByUuid.values.map((c) => Padding(
                                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                                  child: ChoiceChip(
                                    label: Text(c.name),
                                    selected: _categoryFilter == c.uuid,
                                    onSelected: (_) => setState(() => _categoryFilter = c.uuid),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
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
                                  'SKU: ${p.sku}'
                                  '${p.categoryUuid != null ? '  •  ${_categoriesByUuid[p.categoryUuid]?.name ?? ''}' : ''}'
                                  '${p.brandUuid != null ? '  •  ${_brandsByUuid[p.brandUuid]?.name ?? ''}' : ''}'
                                  '  •  Cost: ${_money(p.costPriceMinorUnits)}  •  Price: ${_money(p.salePriceMinorUnits)}',
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
