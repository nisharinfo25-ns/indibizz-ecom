import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui.dart';

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.orderId,
    required this.repository,
  });

  final String orderId;
  final CustomerRepository repository;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  OrderDetail? _order;
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
      final order = await widget.repository.getOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
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

  Future<void> _cancel() async {
    final reason = await promptText(
      context,
      title: 'Cancel Order',
      hint: 'Why do you want to cancel this order?',
      confirmLabel: 'Cancel Order',
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    final ok = await runCustomerAction(
      context,
      () => widget.repository.cancelOrder(widget.orderId, reason.trim()),
      success: 'Order cancelled.',
    );
    if (ok) _load();
  }

  Future<void> _return() async {
    final reason = await promptText(
      context,
      title: 'Request Return',
      hint: 'Explain reason for return (e.g. damaged, wrong size)',
      confirmLabel: 'Submit Return Request',
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    final ok = await runCustomerAction(
      context,
      () => widget.repository.requestReturn(orderId: widget.orderId, reason: reason.trim()),
      success: 'Return request submitted. Our team will review and dispatch pickup.',
    );
    if (ok) _load();
  }

  Future<void> _downloadInvoice(String storagePath) async {
    try {
      final url = await widget.repository.signedInvoice(storagePath);
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) showToast(context, 'Failed to open invoice: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: LoadingView(label: 'Loading order details…')),
      );
    }
    if (_error != null && _order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorNotice(title: 'Could not load order', error: _error.toString(), onRetry: _load),
      );
    }

    final o = _order!;
    final color = orderStatusColor(o.status);
    final cancellable = isCancellable(o.status);
    final returnable = isReturnable(o.status) && o.returnRequest == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(o.orderNumber),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: ListView(
        padding: customerPagePadding,
        children: [
          // Order Header
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order ${o.orderNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        statusLabel(o.status),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Placed on ${formatDate(o.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
                if (o.invoice != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _downloadInvoice(o.invoice!.storagePath),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Download Official Tax Invoice (PDF)'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tracking progress timeline
          Text('Delivery Progress', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SurfaceCard(
            child: _TrackingTimeline(status: o.status),
          ),
          const SizedBox(height: 16),

          // Order Items
          Text('Items in Order (${o.items.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...o.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                child: Row(
                  children: [
                    const ProductThumbnail(imageUrl: null, width: 48, height: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Qty: ${item.quantity} · SKU: ${item.sku}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(formatMoney(item.unitPricePaise * item.quantity), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),

          // Delivery Address
          Text('Delivery Address', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.recipientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${o.line1}${o.line2.isNotEmpty ? ", " + o.line2 : ""}'),
                Text('${o.townName}, ${o.state} ${o.pincode}'),
                Text('Phone: ${o.phone}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Payment Summary
          Text('Payment Breakdown', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal'),
                    Text(formatMoney(o.subtotalPaise)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Shipping Fee'),
                    Text(o.shippingPaise > 0 ? formatMoney(o.shippingPaise) : 'FREE'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Taxes'),
                    Text(o.taxPaise > 0 ? formatMoney(o.taxPaise) : 'Included'),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total (Cash on Delivery)', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      formatMoney(o.totalPaise),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: IndiBizzColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Actions: Cancel / Return
          if (cancellable)
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined, color: IndiBizzColors.error),
              label: const Text('Cancel Order', style: TextStyle(color: IndiBizzColors.error)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          if (returnable)
            ElevatedButton.icon(
              onPressed: _return,
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Request Doorstep Return'),
              style: ElevatedButton.styleFrom(
                backgroundColor: IndiBizzColors.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackingTimeline extends StatelessWidget {
  const _TrackingTimeline({required this.status});
  final String status;

  static const _steps = [
    'Order Placed',
    'Approved',
    'Packed & Picked Up',
    'Out for Delivery',
    'Delivered',
  ];

  int _currentStep() {
    switch (status.toUpperCase()) {
      case 'PENDING_APPROVAL':
        return 0;
      case 'APPROVED':
      case 'READY_FOR_PICKUP':
        return 1;
      case 'PICKUP_REQUESTED':
      case 'PICKED_UP':
      case 'IN_TRANSIT':
      case 'ARRIVED_AT_DESTINATION':
        return 2;
      case 'OUT_FOR_DELIVERY':
        return 3;
      case 'DELIVERED':
      case 'CLOSED':
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentStep();
    final isCancelled = status == 'CANCELLED' || status == 'REJECTED';

    if (isCancelled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: IndiBizzColors.error, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This order has been $status.',
                style: const TextStyle(color: IndiBizzColors.error, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: List.generate(_steps.length, (idx) {
        final isDone = idx <= current;
        final isCurrent = idx == current;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Icon(
                  isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isDone ? IndiBizzColors.success : IndiBizzColors.neutral400,
                  size: 22,
                ),
                if (idx < _steps.length - 1)
                  Container(
                    width: 2,
                    height: 24,
                    color: isDone && idx < current ? IndiBizzColors.success : IndiBizzColors.neutral300,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _steps[idx],
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : (isDone ? FontWeight.w500 : FontWeight.normal),
                    color: isCurrent ? IndiBizzColors.primary : (isDone ? null : IndiBizzColors.neutral500),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
