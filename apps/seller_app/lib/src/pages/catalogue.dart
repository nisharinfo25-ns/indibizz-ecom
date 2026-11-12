import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class CataloguePage extends StatefulWidget {
  const CataloguePage({super.key, required this.repository});
  final OwnerRepository repository;

  @override
  State<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends State<CataloguePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChipRow(
              values: const ['products', 'categories'],
              selected: _tab == 0 ? 'products' : 'categories',
              labelFor: (value) => value == 'products' ? 'Products & stock' : 'Categories',
              onSelected: (value) => setState(() => _tab = value == 'categories' ? 1 : 0),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _ProductsTab(repository: widget.repository),
              _CategoriesTab(repository: widget.repository),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductsTab extends StatefulWidget {
  const _ProductsTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final _search = TextEditingController();
  String? _status;
  bool _lowStock = false;
  String _query = '';
  int _revision = 0;

  static const _statuses = <String?>[null, 'ACTIVE', 'DRAFT', 'ARCHIVED'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor([AdminProduct? product]) async {
    final categories = await widget.repository.listCategories();
    if (!mounted) return;
    if (categories.isEmpty) {
      showToast(context, 'Create a category before adding a product.', error: true);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProductEditorPage(repository: widget.repository, categories: categories, product: product),
      ),
    );
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _search,
                      hint: 'Search product name or SKU',
                      onSubmitted: (value) => setState(() {
                        _query = value.trim();
                        _revision++;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New product'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilterChipRow(
                      values: _statuses,
                      selected: _status,
                      labelFor: (value) => value == null ? 'All' : statusLabel(value),
                      onSelected: (value) => setState(() {
                        _status = value;
                        _revision++;
                      }),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Low stock'),
                    selected: _lowStock,
                    onSelected: (value) => setState(() {
                      _lowStock = value;
                      _revision++;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: OwnerAsyncPage<List<AdminProduct>>(
            key: ValueKey('products-$_revision'),
            scrollable: true,
            load: () => widget.repository.listProducts(status: _status, search: _query.isEmpty ? null : _query, lowStockOnly: _lowStock),
            loadingLabel: 'Loading catalogue…',
            emptyTitle: 'Nothing in this catalogue view',
            emptyMessage: 'Add a product or change the filters to see your catalogue.',
            emptyIcon: Icons.inventory_2_outlined,
            isEmpty: (data) => data.isEmpty,
            builder: (context, products, refresh) => sellerList([
              Row(
                children: [
                  Expanded(child: Text('${products.length} product${products.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
                ],
              ),
              const SizedBox(height: 4),
              for (final product in products)
                OrderCardShell(
                  borderColor: product.isLowStock ? IndiBizzColors.warning : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? IndiBizzColors.darkSurfaceAlt
                                  : IndiBizzColors.canvas,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.inventory_2_outlined, size: 21),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(product.name, style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                  '${product.sku} • ${product.categoryName}${product.weightGrams > 0 ? ' • ${formatWeight(product.weightGrams)}' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(status: product.status),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MoneyText(paise: product.pricePaise, size: 15),
                          Tag(text: 'On hand ${product.quantityOnHand}', icon: Icons.warehouse_outlined),
                          Tag(text: 'Reserved ${product.quantityReserved}', icon: Icons.lock_clock_outlined),
                          Tag(text: 'Available ${product.availableQuantity}', icon: Icons.check_circle_outline_rounded),
                          if (product.isLowStock) const StatusBadge(status: 'LOW', label: 'Low stock'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openEditor(product),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 11)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _adjustStock(product),
                            icon: const Icon(Icons.tune_rounded, size: 15),
                            label: const Text('Adjust stock'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 11)),
                          ),
                          TextButton.icon(
                            onPressed: () => _showMovements(product),
                            icon: const Icon(Icons.history_rounded, size: 15),
                            label: const Text('Movements'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _adjustStock(AdminProduct product) async {
    final formKey = GlobalKey<FormState>();
    final quantity = TextEditingController();
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adjust stock • ${product.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(
                  labelText: 'Quantity change',
                  helperText: 'Use a negative number to remove stock. Example: -2',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed == 0) return 'Enter a non-zero whole number.';
                  if (parsed.abs() > 100000) return 'Quantity change is too large.';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: reason,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'Damaged, recount, supplier receipt…'),
                validator: (value) => (value == null || value.trim().length < 3) ? 'Explain the correction.' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(context, true);
            },
            child: const Text('Post adjustment'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      quantity.dispose();
      reason.dispose();
      return;
    }
    final delta = int.parse(quantity.text.trim());
    final note = reason.text.trim();
    quantity.dispose();
    reason.dispose();
    if (!mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.adjustStock(
        productId: product.id,
        quantityDelta: delta,
        reason: note,
        idempotencyKey: newIdempotencyKey('stock'),
      ),
      success: 'Stock adjustment posted.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _showMovements(AdminProduct product) async {
    try {
      final movements = await widget.repository.inventoryMovements(product.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text('Stock movements • ${product.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Every change is immutable and auditable.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              if (movements.isEmpty)
                const EmptyView(title: 'No movements yet', message: 'Stock changes will appear here with actor and reason.')
              else
                for (final movement in movements)
                  SurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(statusLabel(movement['movement_type']), style: Theme.of(context).textTheme.titleSmall)),
                            Text(
                              '${(movement['quantity_delta'] as num?)?.toInt() ?? 0}',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: ((movement['quantity_delta'] as num?)?.toInt() ?? 0) < 0
                                        ? IndiBizzColors.danger
                                        : IndiBizzColors.success,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'On hand ${movement['on_hand_after'] ?? '—'} • Reserved ${movement['reserved_after'] ?? '—'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if ((movement['reason'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(movement['reason'].toString(), style: Theme.of(context).textTheme.bodySmall),
                        ],
                        const SizedBox(height: 3),
                        Text(formatDateTime(asDate(movement['created_at']), includeYear: true), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString(), error: true);
    }
  }
}

class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  int _revision = 0;

  Future<void> _edit([CategoryInfo? category]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CategoryDialog(category: category),
    );
    if (result == null) return;
    if (!mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.saveCategory(
        id: category?.id,
        name: result['name'] as String,
        slug: (result['slug'] as String).isEmpty ? null : result['slug'] as String,
        description: result['description'] as String,
        sortOrder: result['sort_order'] as int,
        isActive: result['is_active'] as bool,
      ),
      success: category == null ? 'Category created.' : 'Category updated.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Expanded(child: Text('Storefront categories', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('New category'),
              ),
            ],
          ),
        ),
        Expanded(
          child: OwnerAsyncPage<List<CategoryInfo>>(
            key: ValueKey('categories-$_revision'),
            scrollable: true,
            load: widget.repository.listCategories,
            loadingLabel: 'Loading categories…',
            emptyTitle: 'No categories yet',
            emptyMessage: 'Create the first category before adding products.',
            emptyIcon: Icons.category_outlined,
            isEmpty: (data) => data.isEmpty,
            builder: (context, categories, refresh) => sellerList([
              for (final category in categories)
                OrderCardShell(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? IndiBizzColors.darkSurfaceAlt
                              : IndiBizzColors.canvas,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.category_outlined, size: 19),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category.name, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text('${category.productCount} product${category.productCount == 1 ? '' : 's'} • /${category.slug}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      StatusBadge(status: category.isActive ? 'ACTIVE' : 'ARCHIVED', label: category.isActive ? 'Active' : 'Hidden'),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Edit category',
                        onPressed: () => _edit(category),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});
  final CategoryInfo? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.category?.name ?? '');
  late final TextEditingController _slug = TextEditingController(text: widget.category?.slug ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.category?.description ?? '');
  late final TextEditingController _sort = TextEditingController(text: '${widget.category?.sortOrder ?? 0}');
  late bool _active = widget.category?.isActive ?? true;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    _sort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'New category' : 'Edit category'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a category name.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _slug,
                decoration: const InputDecoration(labelText: 'Slug (optional)', hintText: 'grocery-staples'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _sort,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sort order', helperText: 'Lower numbers appear first.'),
                validator: (value) => int.tryParse(value?.trim() ?? '') == null ? 'Enter a whole number.' : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visible in storefront'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'slug': _slug.text.trim(),
              'description': _description.text.trim(),
              'sort_order': int.parse(_sort.text.trim()),
              'is_active': _active,
            });
          },
          child: const Text('Save category'),
        ),
      ],
    );
  }
}

class ProductEditorPage extends StatefulWidget {
  const ProductEditorPage({super.key, required this.repository, required this.categories, this.product});
  final OwnerRepository repository;
  final List<CategoryInfo> categories;
  final AdminProduct? product;

  @override
  State<ProductEditorPage> createState() => _ProductEditorPageState();
}

class _ProductEditorPageState extends State<ProductEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.product == null ? '' : (widget.product!.pricePaise / 100).toStringAsFixed(2),
  );
  late final TextEditingController _compare = TextEditingController(
    text: widget.product?.compareAtPricePaise == null ? '' : (widget.product!.compareAtPricePaise! / 100).toStringAsFixed(2),
  );
  late final TextEditingController _tax = TextEditingController(
    text: widget.product == null ? '0' : (widget.product!.taxRateBps / 100).toStringAsFixed(2),
  );
  late final TextEditingController _hsn = TextEditingController(text: widget.product?.hsnCode ?? '');
  late final TextEditingController _weight = TextEditingController(text: '${widget.product?.weightGrams ?? 0}');
  late final TextEditingController _description = TextEditingController(text: widget.product?.description ?? '');
  late final TextEditingController _threshold = TextEditingController(text: '${widget.product?.lowStockThreshold ?? 5}');
  late final TextEditingController _openingStock = TextEditingController(text: '0');
  late String _categoryId = widget.product?.categoryId ?? widget.categories.first.id;
  late String _status = widget.product?.status ?? 'DRAFT';
  late bool _featured = widget.product?.isFeatured ?? false;
  bool _busy = false;
  PlatformFile? _pendingImage;

  bool get _isEdit => widget.product != null;

  @override
  void dispose() {
    for (final controller in [_name, _sku, _price, _compare, _tax, _hsn, _weight, _description, _threshold, _openingStock]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final pricePaise = parseRupeesToPaise(_price.text);
    final comparePaise = _compare.text.trim().isEmpty ? null : parseRupeesToPaise(_compare.text);
    final taxPercent = double.tryParse(_tax.text.trim()) ?? 0;
    if (pricePaise == null) {
      showToast(context, 'Enter a valid price.', error: true);
      return;
    }
    if (comparePaise != null && comparePaise <= pricePaise) {
      showToast(context, 'Compare-at price must be greater than the selling price.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.repository.saveProduct(
        id: widget.product?.id,
        categoryId: _categoryId,
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        pricePaise: pricePaise,
        compareAtPricePaise: comparePaise,
        taxRateBps: (taxPercent * 100).round(),
        hsnCode: _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
        description: _description.text.trim(),
        weightGrams: int.tryParse(_weight.text.trim()) ?? 0,
        status: _status,
        isFeatured: _featured,
        lowStockThreshold: int.tryParse(_threshold.text.trim()) ?? 5,
        openingStock: _isEdit ? 0 : (int.tryParse(_openingStock.text.trim()) ?? 0),
      );
      final productId = result['id']?.toString() ?? widget.product?.id;
      if (productId == null) throw Exception('The product was saved without an id.');
      if (_pendingImage != null) {
        final file = _pendingImage!;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw Exception('The selected image could not be read.');
        final path = await StorageUploads.uploadProductImage(
          productId: productId,
          bytes: bytes,
          fileName: file.name,
          contentType: _contentType(file.extension),
        );
        await widget.repository.addProductImage(productId: productId, storagePath: path, altText: _name.text.trim(), isPrimary: true);
      }
      if (!mounted) return;
      showToast(context, _isEdit ? 'Product updated.' : 'Product created.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showToast(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final size = await file.length();
    if (size != null && size > 10 * 1024 * 1024) {
      if (mounted) showToast(context, 'Images must be 10 MB or smaller.', error: true);
      return;
    }
    setState(() => _pendingImage = file);
  }

  Future<void> _deleteImage(ProductImage image) async {
    final ok = await confirmAction(context, title: 'Remove image', message: 'This removes the image reference from the product.', destructive: true, confirmLabel: 'Remove');
    if (!ok || !mounted) return;
    final success = await runSellerAction(context, () => widget.repository.deleteProductImage(image.id), success: 'Image removed.');
    if (success && mounted) Navigator.pop(context);
  }

  String _contentType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit product' : 'New product'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: SingleChildScrollView(
            padding: sellerPagePadding,
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DetailSection(
                    title: 'Product identity',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Product name'),
                          textCapitalization: TextCapitalization.words,
                          validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a product name.' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _sku,
                                decoration: const InputDecoration(labelText: 'SKU'),
                                textCapitalization: TextCapitalization.characters,
                                validator: (value) => (value == null || value.trim().isEmpty) ? 'SKU is required.' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: _categorySelector()),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                            DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                            DropdownMenuItem(value: 'ARCHIVED', child: Text('Archived')),
                          ],
                          onChanged: (value) => setState(() => _status = value ?? 'DRAFT'),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _description,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Feature on storefront'),
                          subtitle: const Text('Featured products appear first in the customer catalogue.'),
                          value: _featured,
                          onChanged: (value) => setState(() => _featured = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DetailSection(
                    title: 'Pricing & tax',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _price,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Selling price (₹)'),
                                validator: (value) => parseRupeesToPaise(value ?? '') == null ? 'Enter a valid price.' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _compare,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Compare-at price (₹)', helperText: 'Optional'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _tax,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Tax rate (%)'),
                                validator: (value) {
                                  final parsed = double.tryParse(value?.trim() ?? '');
                                  if (parsed == null || parsed < 0 || parsed > 50) return 'Between 0 and 50.';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _hsn,
                                decoration: const InputDecoration(labelText: 'HSN code', helperText: 'Optional'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _weight,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Weight (grams)'),
                                validator: (value) => (int.tryParse(value?.trim() ?? '') ?? -1) < 0 ? 'Enter grams.' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _threshold,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Low-stock threshold'),
                                validator: (value) => (int.tryParse(value?.trim() ?? '') ?? -1) < 0 ? 'Enter a whole number.' : null,
                              ),
                            ),
                          ],
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _openingStock,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Opening stock', helperText: 'Creates the first immutable stock movement.'),
                            validator: (value) => (int.tryParse(value?.trim() ?? '') ?? -1) < 0 ? 'Enter a whole number.' : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DetailSection(
                    title: 'Images',
                    trailing: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                      label: Text(_pendingImage == null ? 'Choose image' : 'Change image'),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_pendingImage != null)
                          Row(
                            children: [
                              const Icon(Icons.image_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${_pendingImage!.name} • will upload on save', style: Theme.of(context).textTheme.bodySmall)),
                            ],
                          )
                        else if (widget.product?.images.isEmpty ?? true)
                          Text('No image attached yet. Choose a JPG, PNG or WebP up to 10 MB.', style: Theme.of(context).textTheme.bodySmall)
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final image in widget.product!.images)
                                InputChip(
                                  label: Text(image.isPrimary ? 'Primary image' : 'Image'),
                                  onDeleted: _busy ? null : () => _deleteImage(image),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(_busy ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create product')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _categorySelector() {
    return DropdownButtonFormField<String>(
      initialValue: _categoryId,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        for (final category in widget.categories) DropdownMenuItem(value: category.id, child: Text(category.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) => _categoryId = value ?? _categoryId,
      validator: (value) => (value == null || value.isEmpty) ? 'Choose a category.' : null,
    );
  }
}

/// Local helper so the catalogue page can read timestamps without importing
/// the core JSON utilities.
DateTime? asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// Keeps the typed byte payload explicit at call sites that upload evidence.
typedef FileBytes = Uint8List;
