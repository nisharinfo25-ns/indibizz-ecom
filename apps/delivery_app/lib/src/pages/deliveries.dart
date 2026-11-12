import 'package:file_picker/file_picker.dart';
import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui.dart';

class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({super.key, required this.repository});
  final StaffRepository repository;

  @override
  State<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends State<DeliveriesPage> {
  String? _statusFilter;
  List<DeliveryTask> _tasks = [];
  bool _loading = true;
  Object? _error;

  static const _filters = <String?>[
    null,
    'ASSIGNED',
    'ACCEPTED',
    'IN_TRANSIT',
    'OUT_FOR_DELIVERY',
    'ARRIVED_AT_DESTINATION',
    'DELIVERED',
    'DELIVERY_FAILED',
  ];

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
      final list = await widget.repository.listDeliveries(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _tasks = list;
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

  Future<void> _callCustomer(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      showToast(context, 'Cannot launch phone call dialer.', error: true);
    }
  }

  Future<void> _openMap(DeliveryTask task) async {
    final address = '${task.line1}, ${task.townName}, ${task.state} ${task.pincode}';
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _accept(DeliveryTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.acceptDelivery(task.assignmentId),
      success: 'Delivery assignment accepted.',
    );
    if (ok) _load();
  }

  Future<void> _reject(DeliveryTask task) async {
    final reason = await promptText(
      context,
      title: 'Reject delivery assignment',
      hint: 'Why cannot you accept this delivery right now?',
      confirmLabel: 'Reject assignment',
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    final ok = await runStaffAction(
      context,
      () => widget.repository.rejectDelivery(task.assignmentId, reason.trim()),
      success: 'Delivery assignment rejected.',
    );
    if (ok) _load();
  }

  Future<void> _markInTransit(DeliveryTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.markInTransit(task.assignmentId),
      success: 'Marked in transit.',
    );
    if (ok) _load();
  }

  Future<void> _startOutForDelivery(DeliveryTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.startOutForDelivery(task.assignmentId),
      success: 'Started out for delivery! Customer has received OTP on SMS.',
    );
    if (ok) _load();
  }

  Future<void> _markArrived(DeliveryTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.markArrived(task.assignmentId),
      success: 'Arrived at delivery location.',
    );
    if (ok) _load();
  }

  Future<void> _resendOtp(DeliveryTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.resendDeliveryOtp(task.assignmentId),
      success: 'Fresh delivery OTP dispatched to customer.',
    );
    if (ok) _load();
  }

  Future<void> _completeDelivery(DeliveryTask task) async {
    final otpCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: task.customerName);
    final noteCtrl = TextEditingController();
    int? codCollectedPaise = task.codAmountPaise > 0 ? task.codAmountPaise : null;
    String? uploadedPhotoPath;
    bool uploading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.verified_rounded, color: IndiBizzColors.success),
                const SizedBox(width: 8),
                Text('Complete Delivery ${task.shipmentNumber}'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask the customer for the 6-digit delivery OTP sent to their registered phone number.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Customer Delivery OTP *',
                      hintText: 'Enter 6-digit OTP',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Recipient Name',
                      hintText: 'Name of person receiving order',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  if (task.codAmountPaise > 0) ...[
                    const SizedBox(height: 16),
                    SurfaceCard(
                      color: IndiBizzColors.warning.withValues(alpha: 0.1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.currency_rupee_rounded, color: IndiBizzColors.warning),
                              const SizedBox(width: 6),
                              Text(
                                'Cash to Collect: ${formatMoney(task.codAmountPaise)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Verify cash received in full before confirming delivery.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Proof of delivery photo upload
                  OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty) return;
                            final file = result.files.first;
                            if (file.bytes == null) return;

                            setDialogState(() => uploading = true);
                            try {
                              final path = await widget.repository.uploadDeliveryPhoto(
                                shipmentId: task.shipmentId,
                                bytes: file.bytes!,
                                fileName: file.name,
                                contentType: 'image/jpeg',
                              );
                              setDialogState(() {
                                uploadedPhotoPath = path;
                                uploading = false;
                              });
                            } catch (e) {
                              setDialogState(() => uploading = false);
                              if (context.mounted) {
                                showToast(context, 'Failed to upload photo: $e', error: true);
                              }
                            }
                          },
                    icon: Icon(
                      uploadedPhotoPath != null ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
                      color: uploadedPhotoPath != null ? IndiBizzColors.success : null,
                    ),
                    label: Text(uploading
                        ? 'Uploading photo…'
                        : uploadedPhotoPath != null
                            ? 'Proof photo attached'
                            : 'Upload Proof Photo (Optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Delivery Notes (Optional)',
                      hintText: 'Left with security, doorstep, etc.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final otp = otpCtrl.text.trim();
                  if (otp.length != 6) {
                    showToast(dialogContext, 'Please enter the valid 6-digit OTP.', error: true);
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  final ok = await runStaffAction(
                    this.context,
                    () => widget.repository.completeDelivery(
                      assignmentId: task.assignmentId,
                      otp: otp,
                      recipientName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
                      note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                      photoPath: uploadedPhotoPath,
                      codCollectedPaise: codCollectedPaise,
                    ),
                    success: 'Order delivered successfully! Settlement updated.',
                  );
                  if (ok) _load();
                },
                child: const Text('Verify OTP & Deliver'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _failDelivery(DeliveryTask task) async {
    String selectedReason = 'CUSTOMER_UNAVAILABLE';
    final notesCtrl = TextEditingController();

    final okToFail = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Delivery Failure'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select the failure reason. The order will be scheduled for re-attempt or marked as failed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'CUSTOMER_UNAVAILABLE', child: Text('Customer unavailable / unreachable')),
                  DropdownMenuItem(value: 'CUSTOMER_REFUSED', child: Text('Customer refused order')),
                  DropdownMenuItem(value: 'WRONG_ADDRESS', child: Text('Incorrect address / door locked')),
                  DropdownMenuItem(value: 'CASH_NOT_READY', child: Text('Customer did not have cash ready')),
                  DropdownMenuItem(value: 'PACKAGE_DAMAGED', child: Text('Package damaged')),
                  DropdownMenuItem(value: 'CUSTOMER_REQUESTED_RESCHEDULE', child: Text('Customer requested reschedule')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other reason')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedReason = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Explanation / Notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: IndiBizzColors.error, foregroundColor: Colors.white),
              child: const Text('Confirm Failure'),
            ),
          ],
        ),
      ),
    );

    if (okToFail == true && mounted) {
      final ok = await runStaffAction(
        context,
        () => widget.repository.failDelivery(
          assignmentId: task.assignmentId,
          reason: selectedReason,
          notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
        ),
        success: 'Delivery failure recorded.',
      );
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((filter) {
                final selected = _statusFilter == filter;
                final label = filter == null
                    ? 'All'
                    : filter.replaceAll('_', ' ').toLowerCase().split(' ').map((e) => e.isNotEmpty ? '${e[0].toUpperCase()}${e.substring(1)}' : '').join(' ');
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _statusFilter = filter);
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _loading && _tasks.isEmpty
              ? const Center(child: LoadingView(label: 'Loading delivery tasks…'))
              : _error != null && _tasks.isEmpty
                  ? ErrorNotice(
                      title: 'Could not load deliveries',
                      error: _error.toString(),
                      onRetry: _load,
                    )
                  : _tasks.isEmpty
                      ? const Center(
                          child: EmptyState(
                            title: 'No delivery tasks found',
                            message: 'Assignments dispatched to you will appear here.',
                            icon: Icons.local_shipping_outlined,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: deliveryPagePadding,
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return _DeliveryCard(
                                task: task,
                                onCall: () => _callCustomer(task.customerPhone),
                                onMap: () => _openMap(task),
                                onAccept: () => _accept(task),
                                onReject: () => _reject(task),
                                onInTransit: () => _markInTransit(task),
                                onStartOutForDelivery: () => _startOutForDelivery(task),
                                onMarkArrived: () => _markArrived(task),
                                onResendOtp: () => _resendOtp(task),
                                onComplete: () => _completeDelivery(task),
                                onFail: () => _failDelivery(task),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.task,
    required this.onCall,
    required this.onMap,
    required this.onAccept,
    required this.onReject,
    required this.onInTransit,
    required this.onStartOutForDelivery,
    required this.onMarkArrived,
    required this.onResendOtp,
    required this.onComplete,
    required this.onFail,
  });

  final DeliveryTask task;
  final VoidCallback onCall;
  final VoidCallback onMap;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onInTransit;
  final VoidCallback onStartOutForDelivery;
  final VoidCallback onMarkArrived;
  final VoidCallback onResendOtp;
  final VoidCallback onComplete;
  final VoidCallback onFail;

  @override
  Widget build(BuildContext context) {
    final statusColor = orderStatusColor(task.shipmentStatus);
    final isOut = task.shipmentStatus == 'OUT_FOR_DELIVERY' || task.shipmentStatus == 'ARRIVED_AT_DESTINATION';
    final isAssigned = task.assignmentStatus == 'ASSIGNED';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Shipment and order number + status
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.shipmentNumber,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Order: ${task.orderNumber}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Tag(
                  text: task.shipmentStatus.replaceAll('_', ' '),
                  color: statusColor,
                ),
              ],
            ),
            const Divider(height: 20),

            // Customer details and COD
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_pin_circle_rounded, size: 20, color: IndiBizzColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.customerName.isNotEmpty ? task.customerName : 'Customer',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${task.line1}${task.line2.isNotEmpty ? ", " + task.line2 : ""}, ${task.townName}, ${task.pincode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (task.landmark.isNotEmpty)
                        Text(
                          'Landmark: ${task.landmark}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // COD and package count summary
            Row(
              children: [
                SurfaceCard(
                  color: task.codAmountPaise > 0
                      ? IndiBizzColors.warning.withValues(alpha: 0.1)
                      : IndiBizzColors.success.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          task.codAmountPaise > 0 ? Icons.currency_rupee_rounded : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: task.codAmountPaise > 0 ? IndiBizzColors.warning : IndiBizzColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.codAmountPaise > 0 ? 'Collect ${formatMoney(task.codAmountPaise)}' : 'Prepaid (₹0)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: task.codAmountPaise > 0 ? IndiBizzColors.warning : IndiBizzColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tag(text: '${task.packageCount} pkg', icon: Icons.inventory_2_outlined),
                const Spacer(),
                // Phone & Map icon buttons
                if (task.customerPhone != null && task.customerPhone!.isNotEmpty)
                  IconButton(
                    tooltip: 'Call customer',
                    icon: const Icon(Icons.call_rounded, color: IndiBizzColors.primary),
                    onPressed: onCall,
                  ),
                IconButton(
                  tooltip: 'Open address on map',
                  icon: const Icon(Icons.navigation_rounded, color: IndiBizzColors.primary),
                  onPressed: onMap,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons row depending on stage
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isAssigned && task.canAccept) ...[
                  ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Accept Assignment'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(foregroundColor: IndiBizzColors.error),
                  ),
                ],
                if (task.assignmentStatus == 'ACCEPTED' && task.canStart)
                  ElevatedButton.icon(
                    onPressed: onInTransit,
                    icon: const Icon(Icons.directions_bike_rounded, size: 16),
                    label: const Text('Mark In Transit'),
                  ),
                if (task.shipmentStatus == 'IN_TRANSIT')
                  ElevatedButton.icon(
                    onPressed: onStartOutForDelivery,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Start Out for Delivery'),
                  ),
                if (task.shipmentStatus == 'OUT_FOR_DELIVERY')
                  OutlinedButton.icon(
                    onPressed: onMarkArrived,
                    icon: const Icon(Icons.location_on_rounded, size: 16),
                    label: const Text('Mark Arrived'),
                  ),
                if (isOut && task.canDeliver) ...[
                  ElevatedButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.verified_rounded, size: 16),
                    label: const Text('Complete Delivery (Enter OTP)'),
                    style: ElevatedButton.styleFrom(backgroundColor: IndiBizzColors.success, foregroundColor: Colors.white),
                  ),
                  TextButton.icon(
                    onPressed: onResendOtp,
                    icon: const Icon(Icons.sms_rounded, size: 16),
                    label: const Text('Resend OTP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onFail,
                    icon: const Icon(Icons.warning_amber_rounded, size: 16),
                    label: const Text('Report Failed'),
                    style: OutlinedButton.styleFrom(foregroundColor: IndiBizzColors.error),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
