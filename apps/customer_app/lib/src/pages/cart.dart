import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class CartPage extends StatefulWidget {
  const CartPage({
    super.key,
    required this.repository,
    required this.onNavigateToShop,
    required this.onNavigateToCheckout,
  });

  final CustomerRepository repository;
  final VoidCallback onNavigateToShop;
  final VoidCallback onNavigateToCheckout;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  Cart? _cart;
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
      final cart = await widget.repository.getCart();
      if (!mounted) return;
      setState(() {
        _cart = cart;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  Future<void> _updateQty(String productId, int newQty) async {
    if (newQty <= 0) {
      await _removeItem(productId);
      return;
    }
    final ok = await runCustomerAction(
      context,
      () => widget.repository.setQuantity(productId, newQty),
      success: 'Cart updated.',
    );
    if (ok) _load();
  }

  Future<void> _removeItem(String productId) async {
    final ok = await runCustomerAction(
      context,
      () => widget.repository.removeFromCart(productId),
      success: 'Item removed from cart.',
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _cart == null) {
      return const Center(child: LoadingView(label: 'Loading cart…'));
    }
    if (_error != null && _cart == null) {
      return ErrorNotice(title: 'Could not load your cart', error: _error.toString(), onRetry: _load);
    }

    final cart = _cart!;
    if (cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 64, color: IndiBizzColors.neutral400),
              const SizedBox(height: 16),
              Text('Your cart is empty', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Explore our catalogue of products and enjoy Cash on Delivery.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: widget.onNavigateToShop,
                icon: const Icon(Icons.storefront_rounded),
                label: const Text('Start Shopping'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: customerPagePadding,
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                final item = cart.items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SurfaceCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ProductThumbnail(imageUrl: null, width: 64, height: 64),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('SKU: ${item.sku}', style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(item.unitPricePaise),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: IndiBizzColors.primary),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Theme.of(context).dividerColor),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove, size: 16),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _updateQty(item.productId, item.quantity - 1),
                                        ),
                                        Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        IconButton(
                                          icon: const Icon(Icons.add, size: 16),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _updateQty(item.productId, item.quantity + 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: IndiBizzColors.error, size: 20),
                                    tooltip: 'Remove',
                                    onPressed: () => _removeItem(item.productId),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Checkout Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Subtotal (${cart.itemCount} items)', style: Theme.of(context).textTheme.bodySmall),
                          Text(
                            formatMoney(cart.subtotalPaise),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.onNavigateToCheckout,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Checkout'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
