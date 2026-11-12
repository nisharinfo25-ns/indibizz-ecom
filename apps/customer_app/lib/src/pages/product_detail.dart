import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.productId,
    required this.productSlug,
    required this.repository,
    required this.onNavigateToCart,
  });

  final String productId;
  final String productSlug;
  final CustomerRepository repository;
  final VoidCallback onNavigateToCart;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  CatalogProduct? _product;
  List<ProductImage> _images = [];
  final Map<String, String?> _signedUrls = {};
  int _selectedImage = 0;
  int _quantity = 1;
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
      final product = await widget.repository.fetchProductBySlug(widget.productSlug);
      final images = await widget.repository.fetchProductImages(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = product;
        _images = images;
        _loading = false;
      });

      for (final img in images) {
        widget.repository.signedProductImage(img.storagePath).then((url) {
          if (mounted && url != null) {
            setState(() => _signedUrls[img.storagePath] = url);
          }
        });
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  Future<void> _addToCart({bool navigate = false}) async {
    if (_product == null) return;
    final ok = await runCustomerAction(
      context,
      () => widget.repository.addToCart(_product!.id, quantity: _quantity),
      success: 'Added $_quantity item(s) to your cart.',
    );
    if (ok && mounted) {
      if (navigate) {
        widget.onNavigateToCart();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $_quantity "${_product!.name}" to cart'),
            action: SnackBarAction(
              label: 'View Cart',
              onPressed: () {
                widget.onNavigateToCart();
                Navigator.of(context).pop();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: LoadingView(label: 'Loading product details…')),
      );
    }
    if (_error != null && _product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorNotice(title: 'Product not found', error: _error.toString(), onRetry: _load),
      );
    }

    final p = _product!;
    final currentImagePath = _images.isNotEmpty ? _images[_selectedImage].storagePath : p.primaryImagePath;
    final currentUrl = currentImagePath != null ? _signedUrls[currentImagePath] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            tooltip: 'Cart',
            onPressed: () {
              Navigator.of(context).pop();
              widget.onNavigateToCart();
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              // Quantity stepper
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: _quantity < p.availableQuantity ? () => setState(() => _quantity++) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: p.inStock ? () => _addToCart(navigate: false) : null,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: Text(p.inStock ? 'Add to Cart' : 'Out of Stock'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: p.inStock ? () => _addToCart(navigate: true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: IndiBizzColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
                child: const Text('Buy Now'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: customerPagePadding,
        children: [
          // Main Image Viewer
          Center(
            child: ProductThumbnail(
              imageUrl: currentUrl,
              width: 320,
              height: 320,
              borderRadius: 16,
            ),
          ),
          const SizedBox(height: 12),

          // Thumbnail selector row
          if (_images.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_images.length, (idx) {
                final isSelected = idx == _selectedImage;
                final imgUrl = _signedUrls[_images[idx].storagePath];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedImage = idx),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? IndiBizzColors.primary : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ProductThumbnail(imageUrl: imgUrl, width: 56, height: 56),
                    ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 16),

          // Title & Category
          Text(
            p.categoryName.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: IndiBizzColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 4),
          Text(p.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('SKU: ${p.sku}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),

          // Price & Status Card
          SurfaceCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          formatMoney(p.pricePaise),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: IndiBizzColors.primary,
                              ),
                        ),
                        if (p.compareAtPricePaise != null && p.compareAtPricePaise! > p.pricePaise) ...[
                          const SizedBox(width: 8),
                          Text(
                            formatMoney(p.compareAtPricePaise!),
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: IndiBizzColors.neutral500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Inclusive of all taxes · Cash on Delivery available', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                Tag(
                  text: p.inStock ? '${p.availableQuantity} in stock' : 'Out of stock',
                  icon: p.inStock ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                  color: p.inStock ? IndiBizzColors.success : IndiBizzColors.error,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Description Section
          Text('Product Description', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SurfaceCard(
            child: Text(
              p.description != null && p.description!.isNotEmpty
                  ? p.description!
                  : 'Genuine guaranteed product sold with verified delivery tracking and Cash on Delivery option.',
              style: const TextStyle(height: 1.5),
            ),
          ),
          const SizedBox(height: 16),

          // Trust Badges
          Row(
            children: [
              Expanded(
                child: SurfaceCard(
                  child: Column(
                    children: [
                      const Icon(Icons.payments_rounded, color: IndiBizzColors.success, size: 28),
                      const SizedBox(height: 6),
                      Text('Pay on Delivery', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Cash verification', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SurfaceCard(
                  child: Column(
                    children: [
                      const Icon(Icons.verified_outlined, color: IndiBizzColors.primary, size: 28),
                      const SizedBox(height: 6),
                      Text('OTP Protected', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Secure handover', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SurfaceCard(
                  child: Column(
                    children: [
                      const Icon(Icons.assignment_return_outlined, color: IndiBizzColors.warning, size: 28),
                      const SizedBox(height: 6),
                      Text('Easy Returns', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Doorstep pickup', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
