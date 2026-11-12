import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';
import 'product_detail.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onNavigateToCart,
  });

  final CustomerRepository repository;
  final VoidCallback onNavigateToCart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<CatalogProduct> _allProducts = [];
  List<CatalogProduct> _filteredProducts = [];
  final Map<String, String?> _signedUrls = {};
  String? _selectedCategory;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _allProducts = list;
        _applyFilter();
        _loading = false;
      });
      _preloadImages(list);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  void _preloadImages(List<CatalogProduct> products) {
    for (final p in products) {
      if (p.primaryImagePath != null && !_signedUrls.containsKey(p.primaryImagePath)) {
        widget.repository.signedProductImage(p.primaryImagePath).then((url) {
          if (mounted && url != null) {
            setState(() => _signedUrls[p.primaryImagePath!] = url);
          }
        });
      }
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesCat = _selectedCategory == null || p.categoryName == _selectedCategory;
        final matchesQuery = query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.categoryName.toLowerCase().contains(query) ||
            p.sku.toLowerCase().contains(query);
        return matchesCat && matchesQuery;
      }).toList();
    });
  }

  Future<void> _quickAddToCart(CatalogProduct product) async {
    final ok = await runCustomerAction(
      context,
      () => widget.repository.addToCart(product.id, quantity: 1),
      success: 'Added "${product.name}" to your cart.',
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${product.name} to cart'),
          action: SnackBarAction(label: 'View Cart', onPressed: widget.onNavigateToCart),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _allProducts.map((p) => p.categoryName).toSet().toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: customerPagePadding,
        children: [
          // Store banner
          SurfaceCard(
            color: IndiBizzColors.primary.withValues(alpha: 0.08),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct from Trusted Sellers',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: IndiBizzColors.primary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Genuine products, fast local delivery, and Cash on Delivery (COD) at your doorstep.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.verified_user_rounded, size: 40, color: IndiBizzColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search bar
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _applyFilter(),
            decoration: InputDecoration(
              hintText: 'Search products by name or category…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _applyFilter();
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Category Chips
          if (categories.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All Products'),
                      selected: _selectedCategory == null,
                      onSelected: (_) {
                        setState(() => _selectedCategory = null);
                        _applyFilter();
                      },
                    ),
                  ),
                  ...categories.map((cat) {
                    final selected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _selectedCategory = selected ? null : cat);
                          _applyFilter();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Product Grid
          if (_loading && _allProducts.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: LoadingView(label: 'Loading products…')))
          else if (_error != null && _allProducts.isEmpty)
            ErrorNotice(title: 'Could not load store catalogue', error: _error.toString(), onRetry: _load)
          else if (_filteredProducts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: EmptyState(
                  title: 'No products found',
                  message: 'Try clearing your search query or selecting another category.',
                  icon: Icons.search_off_rounded,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 3 : 2);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    final imageUrl = product.primaryImagePath != null ? _signedUrls[product.primaryImagePath] : null;

                    return _ProductCard(
                      product: product,
                      imageUrl: imageUrl,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProductDetailPage(
                              productId: product.id,
                              productSlug: product.slug,
                              repository: widget.repository,
                              onNavigateToCart: widget.onNavigateToCart,
                            ),
                          ),
                        );
                      },
                      onAddToCart: product.inStock ? () => _quickAddToCart(product) : null,
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.imageUrl,
    required this.onTap,
    required this.onAddToCart,
  });

  final CatalogProduct product;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Expanded(
              child: Center(
                child: ProductThumbnail(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 8,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Category & Name
            Text(
              product.categoryName.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: IndiBizzColors.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Price & Stock
            Row(
              children: [
                Text(
                  formatMoney(product.pricePaise),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (product.compareAtPricePaise != null && product.compareAtPricePaise! > product.pricePaise) ...[
                  const SizedBox(width: 4),
                  Text(
                    formatMoney(product.compareAtPricePaise!),
                    style: TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: IndiBizzColors.neutral500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),

            // Add to cart button or out of stock tag
            if (!product.inStock)
              const Container(
                padding: EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.center,
                child: Text('Out of Stock', style: TextStyle(color: IndiBizzColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onAddToCart,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Add to Cart', style: TextStyle(fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
