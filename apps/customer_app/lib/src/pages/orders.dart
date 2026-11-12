import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';
import 'order_detail.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.repository, required this.onNavigateToShop});
  final CustomerRepository repository;
  final VoidCallback onNavigateToShop;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<OrderSummary> _orders = [];
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
      final list = await widget.repository.listOrders();
      if (!mounted) return;
      setState(() {
        _orders = list;
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _orders.isEmpty) {
      return const Center(child: LoadingView(label: 'Loading orders…'));
    }
    if (_error != null && _orders.isEmpty) {
      return ErrorNotice(title: 'Could not load your orders', error: _error.toString(), onRetry: _load);
    }
    if (_orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 64, color: IndiBizzColors.neutral400),
              const SizedBox(height: 16),
              Text('No orders yet', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'When you place orders, their delivery tracking and status will show up here.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: widget.onNavigateToShop,
                icon: const Icon(Icons.storefront_rounded),
                label: const Text('Explore Catalogue'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: customerPagePadding,
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          final color = orderStatusColor(order.status);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailPage(
                            orderId: order.id,
                            repository: widget.repository,
                          ),
                        ),
                      )
                      .then((_) => _load());
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            statusLabel(order.status),
                            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${order.itemCount} item(s) · Cash on Delivery', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          formatMoney(order.totalPaise),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.arrow_forward_rounded, size: 16, color: IndiBizzColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Track delivery & view details',
                          style: TextStyle(fontSize: 12, color: IndiBizzColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
