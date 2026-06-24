import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/party/party.dart';
import '../../../core/system/providers.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/quantity_stepper.dart';
import '../inventory/product.dart';
import 'purchase_repository.dart';

class _CartLine {
  _CartLine(this.product, this.quantity, this.unitCostMinorUnits);
  final Product product;
  int quantity;
  int unitCostMinorUnits;
  int get totalMinorUnits => quantity * unitCostMinorUnits;
}

/// Same two-pane POS layout as SaleEntryScreen (search/cart left,
/// sticky checkout right) for visual and behavioral consistency between
/// the two cart-style entry screens.
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
  int get _itemCount => _cart.fold(0, (sum, l) => sum + l.quantity);

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
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search product...',
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
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text('Cost: ${_money(p.costPriceMinorUnits)}'),
                            trailing: Chip(label: Text('Stock: ${p.stockQuantity}'), side: BorderSide.none),
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
                        Text('Search a product above to add a line', style: TextStyle(color: Colors.grey.shade600)),
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
                                      '${_money(line.unitCostMinorUnits)} each',
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
          Text('Purchase Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<Party>(
            initialValue: _selectedSupplier,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: _suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
            onChanged: (v) => setState(() => _selectedSupplier = v),
          ),
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
                : const Text('Save Purchase'),
          ),
        ],
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);
