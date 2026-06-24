import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/party/party.dart';
import '../../../core/system/providers.dart';
import '../../../shared/currency/currency.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/quantity_stepper.dart';
import '../../../shared/widgets/read_only_banner.dart';
import '../inventory/category.dart';
import '../inventory/product.dart';
import 'invoice_pdf.dart';
import 'sale.dart';
import 'sale_repository.dart';
import 'sales_history_screen.dart';

class _CartLine {
  _CartLine(this.product, this.quantity);
  final Product product;
  int quantity;
  int get totalMinorUnits => quantity * product.salePriceMinorUnits;
}

/// POS-style layout: a browsable product grid (search + category filter
/// chips, like ProductListScreen) on the left, the cart and checkout
/// summary on the right. Previously this only ever showed products
/// through a type-to-search dropdown with nothing displayed by
/// default — a product you'd just added was easy to miss if you didn't
/// know to search for its exact name. Browsing fixes that directly.
class SaleEntryScreen extends ConsumerStatefulWidget {
  const SaleEntryScreen({super.key});

  @override
  ConsumerState<SaleEntryScreen> createState() => _SaleEntryScreenState();
}

class _SaleEntryScreenState extends ConsumerState<SaleEntryScreen> {
  final _searchController = TextEditingController();
  List<Product>? _allProducts;
  Map<String, Category> _categoriesByUuid = {};
  String? _categoryFilter;
  String _query = '';
  final List<_CartLine> _cart = [];

  PaymentMethod _paymentMethod = PaymentMethod.cash;
  List<Party> _customers = [];
  Party? _selectedCustomer;
  bool _submitting = false;
  String _businessName = '';
  String? _currency;

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
    final partyRepo = await ref.read(partyRepositoryProvider.future);
    final productRepo = await ref.read(productRepositoryProvider.future);
    final categoryRepo = await ref.read(categoryRepositoryProvider.future);
    final business = await ref.read(currentBusinessProvider.future);

    final customers = await partyRepo.list(
      businessId: businessId,
      type: PartyType.customer,
    );
    final products = await productRepo.list(businessId: businessId);
    final categories = await categoryRepo.list(businessId: businessId);

    if (mounted) {
      setState(() {
        _customers = customers;
        _allProducts = products;
        _categoriesByUuid = {for (final c in categories) c.uuid: c};
        _businessName = business.name;
        _currency = business.baseCurrency;
      });
    }
  }

  List<Product> get _filteredProducts {
    final all = _allProducts ?? const [];
    return all.where((p) {
      final matchesQuery =
          _query.isEmpty ||
          p.name.toLowerCase().contains(_query) ||
          p.sku.toLowerCase().contains(_query);
      final matchesCategory =
          _categoryFilter == null || p.categoryUuid == _categoryFilter;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  void _addToCart(Product product) {
    setState(() {
      final existingIndex = _cart.indexWhere(
        (l) => l.product.uuid == product.uuid,
      );
      if (existingIndex != -1) {
        _cart[existingIndex].quantity++;
      } else {
        _cart.add(_CartLine(product, 1));
      }
    });
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
            .map(
              (l) => SaleLineInput(
                productUuid: l.product.uuid,
                quantity: l.quantity,
                unitPriceMinorUnits: l.product.salePriceMinorUnits,
              ),
            )
            .toList(),
      );

      final productsByUuid = {for (final l in _cart) l.product.uuid: l.product};
      final savedCustomer = _selectedCustomer;
      final businessName = _businessName;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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
          ),
        );
        setState(() {
          _cart.clear();
          _selectedCustomer = null;
          _paymentMethod = PaymentMethod.cash;
        });
      }
      await _load(); // refresh stock quantities shown in the product grid
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = ref.watch(isReadOnlyProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Sales History & Returns',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isReadOnly) const ReadOnlyBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildProductBrowser(context)),
                Container(width: 1, color: Theme.of(context).dividerColor),
                SizedBox(
                  width: 380,
                  child: _buildCartAndCheckout(context, isReadOnly),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductBrowser(BuildContext context) {
    if (_allProducts == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allProducts!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('No products yet — add one from the Products screen.'),
          ],
        ),
      );
    }

    final products = _filteredProducts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Scan or search product...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (_categoriesByUuid.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
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
                  ..._categoriesByUuid.values.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(c.name),
                        selected: _categoryFilter == c.uuid,
                        onSelected: (_) =>
                            setState(() => _categoryFilter = c.uuid),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text(
                      'No matching products',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = (constraints.maxWidth / 220)
                          .floor()
                          .clamp(1, 6);
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.3,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) => _ProductTile(
                          product: products[index],
                          onTap: _addToCart,
                          currency: _currency,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartAndCheckout(BuildContext context, bool isReadOnly) {
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'Cart',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Tap a product to add it',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final line = _cart[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${formatMoney(line.product.salePriceMinorUnits, _currency)} each',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
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
                                onIncrement: () =>
                                    setState(() => line.quantity++),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  formatMoney(line.totalMinorUnits, _currency),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: PaymentMethod.values
                      .map(
                        (m) => DropdownMenuItem(value: m, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _paymentMethod = v ?? PaymentMethod.cash),
                ),
                if (_paymentMethod == PaymentMethod.credit) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<Party>(
                    initialValue: _selectedCustomer,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: _customers
                        .map(
                          (c) =>
                              DropdownMenuItem(value: c, child: Text(c.name)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCustomer = v),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Items',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    Text('$_itemCount'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      formatMoney(_total, _currency),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: (_submitting || _cart.isEmpty || isReadOnly)
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Complete Sale (F3)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap, this.currency});

  final Product product;
  final void Function(Product) onTap;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stockQuantity <= 0;
    final lowStock =
        !outOfStock && product.stockQuantity <= product.reorderLevel;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: outOfStock ? null : () => onTap(product),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.accent,
                  size: 18,
                ),
              ),
              const Spacer(),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatMoney(product.salePriceMinorUnits, currency),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                outOfStock ? 'Out of stock' : 'Stock: ${product.stockQuantity}',
                style: TextStyle(
                  fontSize: 11,
                  color: outOfStock || lowStock
                      ? AppColors.destructive
                      : Colors.grey.shade600,
                  fontWeight: outOfStock || lowStock ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
