import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui.dart';

Future<void> openAdminOrder(BuildContext context, OwnerRepository repository, String orderId) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => AdminOrderPage(repository: repository, orderId: orderId)),
  );
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.repository});
  final OwnerRepository repository;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _search = TextEditingController();
  String? _status;
  String _query = '';
  int _revision = 0;

  static const _statuses = <String?>[
    null,
    'PENDING_APPROVAL',
    'APPROVED',
    'READY_FOR_PICKUP',
    'PICKUP_REQUESTED',
    'PICKED_UP',
    'OUT_FOR_DELIVERY',
    'DELIVERED',
    'REJECTED',
    'CANCELLED',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _search,
                      hint: 'Search order number, customer or phone',
                      onSubmitted: (value) => setState(() {
                        _query = value.trim();
                        _revision++;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Search',
                    onPressed: () => setState(() {
                      _query = _search.text.trim();
                      _revision++;
                    }),
                    icon: const Icon(Icons.search_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChipRow(
                  values: _statuses,
                  selected: _status,
                  labelFor: (value) => value == null ? 'All orders' : statusLabel(value),
                  onSelected: (value) => setState(() {
                    _status = value;
                    _revision++;
                  }),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: OwnerAsyncPage<List<AdminOrderSummary>>(
            key: ValueKey('orders-$_revision'),
            scrollable: true,
            load: () => widget.repository.listOrders(status: _status, search: _query.isEmpty ? null : _query),
            loadingLabel: 'Loading orders…',
            emptyTitle: 'No orders in this view',
            emptyMessage: 'Orders placed by customers will appear here for approval and dispatch.',
            emptyIcon: Icons.receipt_long_outlined,
            isEmpty: (data) => data.isEmpty,
            builder: (context, orders, refresh) => sellerList([
              Row(
                children: [
                  Expanded(child: Text('${orders.length} order${orders.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final order in orders)
                OrderCardShell(
                  onTap: () async {
                    await openAdminOrder(context, widget.repository, order.id);
                    if (context.mounted) {
                      setState(() => _revision++);
                    }
                  },
                  borderColor: order.status == 'PENDING_APPROVAL' ? IndiBizzColors.warning : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: Text(order.orderNumber, style: Theme.of(context).textTheme.titleSmall)),
                                const SizedBox(width: 7),
                                StatusBadge(status: order.status),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${order.customerName}${order.townName.isEmpty ? '' : ' • ${order.townName}'} • ${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (order.customerPhone != null) Tag(text: formatPhone(order.customerPhone), icon: Icons.phone_outlined),
                                Tag(text: formatDateTime(order.createdAt), icon: Icons.schedule_rounded),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(paise: order.totalPaise),
                          const SizedBox(height: 4),
                          Text('COD ${formatMoney(order.codAmountPaise)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5)),
                          const SizedBox(height: 8),
                          const Icon(Icons.chevron_right_rounded, size: 18),
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
}

class AdminOrderPage extends StatefulWidget {
  const AdminOrderPage({super.key, required this.repository, required this.orderId});
  final OwnerRepository repository;
  final String orderId;

  @override
  State<AdminOrderPage> createState() => _AdminOrderPageState();
}

class _AdminOrderPageState extends State<AdminOrderPage> {
  late Future<AdminOrderDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getOrderAdmin(widget.orderId);
  }

  void _reload() => setState(() => _future = widget.repository.getOrderAdmin(widget.orderId));

  Future<void> _action(Future<Object?> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await runSellerAction(context, action, success: success);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order details'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<AdminOrderDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(label: 'Loading the complete order…');
          }
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final data = snapshot.data;
          if (data == null) return const LoadingView();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 940),
              child: SingleChildScrollView(
                padding: sellerPagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OrderHeader(detail: data),
                    const SizedBox(height: 12),
                    _ActionBar(
                      detail: data,
                      busy: _busy,
                      onApprove: () => _approve(data),
                      onReject: () => _reject(data),
                      onAddPackage: () => _addPackage(data),
                      onSeal: (packageId) => _action(() => widget.repository.sealPackage(packageId), 'Package sealed.'),
                      onReady: () => _ready(data),
                      onRequestPickup: () => _requestPickup(data),
                      onGetOtp: () => _showOtp(data),
                      onRegenerateOtp: () => _regenerateOtp(data),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        final items = _ItemsCard(detail: data);
                        final side = Column(
                          children: [
                            _CustomerCard(detail: data),
                            const SizedBox(height: 12),
                            _PackagesCard(
                              detail: data,
                              busy: _busy,
                              onSeal: (packageId) => _action(() => widget.repository.sealPackage(packageId), 'Package sealed.'),
                            ),
                            const SizedBox(height: 12),
                            _PickupCard(detail: data),
                            const SizedBox(height: 12),
                            _ShippingCard(detail: data),
                            const SizedBox(height: 12),
                            _DocumentsCard(detail: data),
                          ],
                        );
                        if (!wide) {
                          return Column(children: [items, const SizedBox(height: 12), side]);
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: items),
                            const SizedBox(width: 12),
                            Expanded(flex: 4, child: side),
                          ],
                        );
                      },
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

  Future<void> _approve(AdminOrderDetail data) async {
    final count = await promptText(
      context,
      title: 'Approve order',
      hint: 'Number of packages',
      initialValue: '${data.packages.isEmpty ? 1 : data.packages.length}',
      helper: 'Stock is consumed and an invoice is issued immediately.',
      keyboardType: TextInputType.number,
      confirmLabel: 'Approve & issue invoice',
    );
    if (count == null) return;
    final packageCount = int.tryParse(count);
    if (packageCount == null || packageCount < 1 || packageCount > 20) {
      if (mounted) showToast(context, 'Package count must be between 1 and 20.', error: true);
      return;
    }
    await _action(() => widget.repository.approveOrder(data.order.id, packageCount: packageCount), 'Order approved and invoice issued.');
  }

  Future<void> _reject(AdminOrderDetail data) async {
    final reason = await askReason(context, title: 'Reject order', hint: 'Why can this order not be accepted?', confirmLabel: 'Reject order');
    if (reason == null) return;
    await _action(() => widget.repository.rejectOrder(data.order.id, reason), 'Order rejected. Reserved stock was released.');
  }

  Future<void> _addPackage(AdminOrderDetail data) async {
    final weight = await promptText(
      context,
      title: 'Add a package',
      hint: 'Weight in grams (optional)',
      keyboardType: TextInputType.number,
      required: false,
      confirmLabel: 'Add package',
    );
    if (weight == null) return;
    final grams = int.tryParse(weight) ?? 0;
    await _action(() => widget.repository.addPackage(data.order.id, weightGrams: grams), 'Package added.');
  }

  Future<void> _ready(AdminOrderDetail data) async {
    final ok = await confirmAction(
      context,
      title: 'Mark ready for pickup',
      message: 'Every package must be sealed. This tells dispatch that the parcel can be collected.',
      confirmLabel: 'Mark ready',
    );
    if (!ok) return;
    await _action(() => widget.repository.markReadyForPickup(data.order.id), 'Order is ready for pickup.');
  }

  Future<void> _requestPickup(AdminOrderDetail data) async {
    final ok = await confirmAction(
      context,
      title: 'Request pickup',
      message: 'A pickup OTP will be generated. Share it only at physical handover after counting and checking the packages.',
      confirmLabel: 'Request pickup',
    );
    if (!ok) return;
    await _action(() async {
      final result = await widget.repository.requestPickup(data.order.id);
      final otp = result['otp'];
      if (otp != null && mounted) {
        await _showOtpValue(context, otp.toString(), pickupNumber: result['pickup_number']?.toString());
      }
      return result;
    }, 'Pickup requested.');
  }

  Future<void> _showOtp(AdminOrderDetail data) async {
    final pickup = data.pickup;
    if (pickup == null) return;
    var otp = pickup.otp;
    if (otp == null || otp.isEmpty) {
      try {
        final result = await widget.repository.getPickupOtp(pickup.id);
        otp = result['otp']?.toString();
      } catch (error) {
        if (mounted) showToast(context, error.toString(), error: true);
        return;
      }
    }
    if (otp == null || otp.isEmpty) {
      if (mounted) showToast(context, 'No active pickup OTP exists. Regenerate one.', error: true);
      return;
    }
    if (mounted) await _showOtpValue(context, otp, pickupNumber: pickup.pickupNumber);
  }

  Future<void> _regenerateOtp(AdminOrderDetail data) async {
    final pickup = data.pickup;
    if (pickup == null) return;
    final ok = await confirmAction(
      context,
      title: 'Regenerate pickup OTP',
      message: 'The previous OTP will stop working immediately. Share the new code only at handover.',
      confirmLabel: 'Regenerate',
    );
    if (!ok) return;
    try {
      final result = await widget.repository.regeneratePickupOtp(pickup.id);
      final otp = result['otp']?.toString();
      if (otp != null && mounted) {
        await _showOtpValue(context, otp, pickupNumber: pickup.pickupNumber);
      }
      _reload();
    } catch (error) {
      if (mounted) showToast(context, error.toString(), error: true);
    }
  }
}

Future<void> _showOtpValue(BuildContext context, String otp, {String? pickupNumber}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(pickupNumber == null ? 'Pickup OTP' : 'Pickup OTP • $pickupNumber'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            otp,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8),
          ),
          const SizedBox(height: 10),
          const Text('Share this code with the delivery person only after physically counting and checking every sealed package.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          onPressed: () async {
            await copyText(context, otp, label: 'Pickup OTP');
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy OTP'),
        ),
      ],
    ),
  );
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.detail});
  final AdminOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.orderNumber, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 5),
                    Text(
                      'Placed ${formatDateTime(order.createdAt, includeYear: true)} • ${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              _HeaderStat(label: 'Order total', value: formatMoney(order.totalPaise)),
              _HeaderStat(label: 'COD amount', value: formatMoney(order.codAmountPaise)),
              _HeaderStat(label: 'Payment', value: statusLabel(order.paymentStatus)),
              _HeaderStat(label: 'Invoice', value: order.invoice?.invoiceNumber ?? 'Not issued'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 9, letterSpacing: 0.9, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.detail,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onAddPackage,
    required this.onSeal,
    required this.onReady,
    required this.onRequestPickup,
    required this.onGetOtp,
    required this.onRegenerateOtp,
  });

  final AdminOrderDetail detail;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onAddPackage;
  final ValueChanged<String> onSeal;
  final VoidCallback onReady;
  final VoidCallback onRequestPickup;
  final VoidCallback onGetOtp;
  final VoidCallback onRegenerateOtp;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    final pickup = detail.pickup;
    final widgets = <Widget>[];
    if (order.status == 'PENDING_APPROVAL') {
      widgets.add(FilledButton.icon(onPressed: busy ? null : onApprove, icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Approve order')));
      widgets.add(OutlinedButton.icon(
        onPressed: busy ? null : onReject,
        icon: const Icon(Icons.close_rounded, size: 17),
        label: const Text('Reject'),
        style: OutlinedButton.styleFrom(foregroundColor: IndiBizzColors.danger),
      ));
    }
    if (order.status == 'APPROVED' || order.status == 'READY_FOR_PICKUP') {
      widgets.add(OutlinedButton.icon(onPressed: busy ? null : onAddPackage, icon: const Icon(Icons.add_box_outlined, size: 17), label: const Text('Add package')));
    }
    if (order.status == 'APPROVED') {
      final pending = detail.packages.where((p) => !p.isSealed).toList();
      if (pending.isNotEmpty) {
        widgets.add(OutlinedButton.icon(
          onPressed: busy ? null : () => onSeal(pending.first.id),
          icon: const Icon(Icons.lock_outline_rounded, size: 17),
          label: Text('Seal next package (${pending.length} left)'),
        ));
      } else {
        widgets.add(FilledButton.icon(onPressed: busy ? null : onReady, icon: const Icon(Icons.inventory_rounded, size: 17), label: const Text('Mark ready for pickup')));
      }
    }
    if (order.status == 'READY_FOR_PICKUP') {
      widgets.add(FilledButton.icon(onPressed: busy ? null : onRequestPickup, icon: const Icon(Icons.local_shipping_outlined, size: 17), label: const Text('Request pickup')));
    }
    if (pickup != null) {
      widgets.add(OutlinedButton.icon(onPressed: busy ? null : onGetOtp, icon: const Icon(Icons.password_rounded, size: 17), label: const Text('View pickup OTP')));
      if (pickup.status == 'REQUESTED' || pickup.status == 'ASSIGNED') {
        widgets.add(TextButton.icon(onPressed: busy ? null : onRegenerateOtp, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Regenerate OTP')));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(spacing: 8, runSpacing: 8, children: widgets),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.detail});
  final AdminOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    return DetailSection(
      title: 'Items & totals',
      child: Column(
        children: [
          for (final item in order.items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text('${item.sku} • ${item.quantity} × ${formatMoney(item.unitPricePaise)}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                MoneyText(paise: item.lineTotalPaise, size: 13),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Divider(),
          const SizedBox(height: 6),
          KeyValueRow(label: 'Subtotal', value: formatMoney(order.subtotalPaise)),
          if (order.discountPaise > 0) KeyValueRow(label: 'Discount', value: '-${formatMoney(order.discountPaise)}'),
          KeyValueRow(label: 'Tax', value: formatMoney(order.taxPaise)),
          KeyValueRow(label: 'Shipping', value: order.shippingPaise == 0 ? 'Free' : formatMoney(order.shippingPaise)),
          const Divider(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Collect on delivery', style: Theme.of(context).textTheme.titleSmall)),
              MoneyText(paise: order.codAmountPaise, size: 18),
            ],
          ),
          if (order.customerNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            InlineNotice(title: 'Customer note', message: order.customerNote, tone: StatusTone.info),
          ],
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.detail});
  final AdminOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    return DetailSection(
      title: 'Delivery address',
      trailing: IconButton(
        tooltip: 'Call customer',
        onPressed: () => launchUrl(Uri(scheme: 'tel', path: order.phone)),
        icon: const Icon(Icons.call_outlined, size: 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.recipientName, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 3),
          Text(formatPhone(order.phone), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(order.addressLine, style: Theme.of(context).textTheme.bodyMedium),
          if (detail.customer.email != null && detail.customer.email!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(detail.customer.email!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _PackagesCard extends StatelessWidget {
  const _PackagesCard({required this.detail, required this.busy, required this.onSeal});
  final AdminOrderDetail detail;
  final bool busy;
  final ValueChanged<String> onSeal;

  @override
  Widget build(BuildContext context) {
    if (detail.packages.isEmpty) {
      return const DetailSection(
        title: 'Packages',
        child: Text('Packages are created when the order is approved.'),
      );
    }
    return DetailSection(
      title: 'Packages',
      trailing: Text('${detail.packages.length}', style: Theme.of(context).textTheme.bodySmall),
      child: Column(
        children: [
          for (final package in detail.packages)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(package.packageNumber, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5))),
                            const SizedBox(width: 6),
                            StatusBadge(status: package.status),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${package.isSealed ? 'Sealed' : 'Unsealed'} • ${formatWeight(package.weightGrams)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  if (!package.isSealed)
                    TextButton(
                      onPressed: busy ? null : () => onSeal(package.id),
                      child: const Text('Seal'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.detail});
  final AdminOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final pickup = detail.pickup;
    if (pickup == null) {
      return const DetailSection(title: 'Pickup', child: Text('No pickup has been requested yet.'));
    }
    return DetailSection(
      title: 'Pickup',
      trailing: StatusBadge(status: pickup.status),
      child: Column(
        children: [
          KeyValueRow(label: 'Pickup number', value: pickup.pickupNumber),
          KeyValueRow(label: 'Packages expected', value: '${pickup.packageCountExpected}'),
          KeyValueRow(label: 'Packages verified', value: '${pickup.packageCountVerified}'),
          KeyValueRow(label: 'Barcode scans', value: '${pickup.scannedPackages}'),
          KeyValueRow(label: 'Condition', value: statusLabel(pickup.condition ?? 'PENDING')),
          KeyValueRow(label: 'Assigned to', value: pickup.assignment?.staffName ?? 'Awaiting assignment'),
          if (pickup.otp != null) ...[
            const SizedBox(height: 8),
            InlineNotice(
              title: 'Pickup OTP',
              message: '${pickup.otp} • share only at physical handover',
              tone: StatusTone.pending,
            ),
          ],
        ],
      ),
    );
  }
}

class _ShippingCard extends StatelessWidget {
  const _ShippingCard({required this.detail});
  final AdminOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final shipment = detail.order.shipment;
    return DetailSection(
      title: 'Shipment',
      child: Column(
        children: [
          if (shipment != null) ...[
            KeyValueRow(label: 'Shipment number', value: shipment.shipmentNumber),
            KeyValueRow(label: 'Status', value: statusLabel(shipment.status)),
            KeyValueRow(label: 'Packages', value: '${shipment.packageCount}'),
            KeyValueRow(label: 'Expected COD', value: formatMoney(shipment.expectedCodPaise)),
          ] else
            const Text('The shipment is created when the order is approved.'),
          if (detail.deliveryAssignmentId != null) ...[
            const SizedBox(height: 6),
            InlineNotice(
              tone: StatusTone.info,
              title: 'Delivery assignment',
              message: '${statusLabel(detail.deliveryStatus)}${detail.deliveryStaffUserId == null ? '' : ' • assigned in Logistics'}',
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.detail});
  final AdminOrderDetail detail;

  Future<void> _generate(BuildContext context, String type, {String? shipmentId, String? pickupId}) async {
    try {
      final result = await const _DocumentLoader().load(detail, type, shipmentId: shipmentId, pickupId: pickupId);
      final url = result['signed_url']?.toString();
      if (url == null || url.isEmpty) throw Exception('The document was generated without a download URL.');
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open the generated document.');
    } catch (error) {
      if (context.mounted) showToast(context, error.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = detail.order;
    return DetailSection(
      title: 'Documents',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: order.invoice == null ? null : () => _generate(context, 'invoice'),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Invoice PDF'),
          ),
          OutlinedButton.icon(
            onPressed: order.shipment == null ? null : () => _generate(context, 'shipping_label', shipmentId: order.shipment!.id),
            icon: const Icon(Icons.qr_code_2_rounded, size: 16),
            label: const Text('Shipping label'),
          ),
          OutlinedButton.icon(
            onPressed: detail.pickup == null ? null : () => _generate(context, 'pickup_manifest', pickupId: detail.pickup!.id),
            icon: const Icon(Icons.checklist_rounded, size: 16),
            label: const Text('Pickup manifest'),
          ),
        ],
      ),
    );
  }
}

/// Keeps document generation callable without exposing repository plumbing to
/// the document card. The loader receives the current order snapshot.
class _DocumentLoader {
  const _DocumentLoader();

  Future<Map<String, dynamic>> load(
    AdminOrderDetail detail,
    String type, {
    String? shipmentId,
    String? pickupId,
  }) async {
    return OwnerRepository(IndiBizz.client).generateDocument(
      type: type,
      orderId: detail.order.id,
      shipmentId: shipmentId,
      pickupId: pickupId,
    );
  }
}
