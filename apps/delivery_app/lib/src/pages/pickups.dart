import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class PickupsPage extends StatefulWidget {
  const PickupsPage({super.key, required this.repository});
  final StaffRepository repository;

  @override
  State<PickupsPage> createState() => _PickupsPageState();
}

class _PickupsPageState extends State<PickupsPage> {
  String? _statusFilter;
  List<PickupTask> _tasks = [];
  bool _loading = true;
  Object? _error;

  static const _filters = <String?>[
    null,
    'ASSIGNED',
    'ACCEPTED',
    'ARRIVED',
    'IN_PROGRESS',
    'VERIFIED',
    'FAILED',
    'CANCELLED',
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
      final list = await widget.repository.listPickups(status: _statusFilter);
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

  Future<void> _accept(PickupTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.acceptPickup(task.assignmentId),
      success: 'Pickup assignment accepted.',
    );
    if (ok) _load();
  }

  Future<void> _reject(PickupTask task) async {
    final reason = await promptText(
      context,
      title: 'Reject pickup assignment',
      hint: 'Explain reason for rejection',
      confirmLabel: 'Reject',
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    final ok = await runStaffAction(
      context,
      () => widget.repository.rejectPickup(task.assignmentId, reason.trim()),
      success: 'Pickup assignment rejected.',
    );
    if (ok) _load();
  }

  Future<void> _arrive(PickupTask task) async {
    final ok = await runStaffAction(
      context,
      () => widget.repository.arriveAtPickup(task.assignmentId),
      success: 'Marked arrived at pickup location.',
    );
    if (ok) _load();
  }

  Future<void> _scanPackage(PickupTask task) async {
    final scanCtrl = TextEditingController();
    final barcode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan or Enter Package Barcode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the package barcode or order tracking number to register custody.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: scanCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Package / Order Code *',
                hintText: 'e.g. PKG-1234 or ORD-5678',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(scanCtrl.text.trim()),
            child: const Text('Submit Scan'),
          ),
        ],
      ),
    );

    if (barcode == null || barcode.isEmpty || !mounted) return;

    final ok = await runStaffAction(
      context,
      () => widget.repository.scanPackage(assignmentId: task.assignmentId, rawCode: barcode),
      success: 'Package scanned and custody logged.',
    );
    if (ok) _load();
  }

  Future<void> _verifyPickup(PickupTask task) async {
    final otpCtrl = TextEditingController();
    final countCtrl = TextEditingController(text: '${task.packageCountExpected}');
    String condition = 'GOOD';
    final noteCtrl = TextEditingController();

    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Verify Pickup ${task.pickupNumber}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the secret Pickup OTP provided by the seller/store manager at handoff.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Pickup OTP *',
                    hintText: 'Enter 6-digit OTP',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Verified Package Count *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: condition,
                  decoration: const InputDecoration(labelText: 'Package Condition', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'GOOD', child: Text('Good Condition / Intact')),
                    DropdownMenuItem(value: 'DAMAGED', child: Text('Damaged / Broken Seal')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => condition = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final otp = otpCtrl.text.trim();
                final count = int.tryParse(countCtrl.text.trim()) ?? 0;
                if (otp.length != 6) {
                  showToast(dialogContext, 'Enter valid 6-digit OTP', error: true);
                  return;
                }
                if (count <= 0) {
                  showToast(dialogContext, 'Package count must be at least 1', error: true);
                  return;
                }
                Navigator.of(dialogContext).pop(true);
                final ok = await runStaffAction(
                  this.context,
                  () => widget.repository.verifyPickup(
                    assignmentId: task.assignmentId,
                    otp: otp,
                    packageCount: count,
                    condition: condition,
                    notes: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  ),
                  success: 'Pickup verified! Package is now officially in transit.',
                );
                if (ok) _load();
              },
              child: const Text('Verify & Take Custody'),
            ),
          ],
        ),
      ),
    );
    if (verified == true) _load();
  }

  Future<void> _failPickup(PickupTask task) async {
    final reasonCtrl = TextEditingController();
    bool damaged = false;

    final failed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Pickup Failure'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Failure Reason *',
                  hintText: 'Seller not present, order not ready, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('Package is damaged or tampered'),
                value: damaged,
                onChanged: (val) => setDialogState(() => damaged = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
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
              child: const Text('Confirm Pickup Failed'),
            ),
          ],
        ),
      ),
    );

    if (failed == true && mounted && reasonCtrl.text.trim().isNotEmpty) {
      final ok = await runStaffAction(
        context,
        () => widget.repository.failPickup(
          assignmentId: task.assignmentId,
          reason: reasonCtrl.text.trim(),
          packageDamaged: damaged,
        ),
        success: 'Pickup failure logged.',
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
              ? const Center(child: LoadingView(label: 'Loading pickup assignments…'))
              : _error != null && _tasks.isEmpty
                  ? ErrorNotice(
                      title: 'Could not load pickups',
                      error: _error.toString(),
                      onRetry: _load,
                    )
                  : _tasks.isEmpty
                      ? const Center(
                          child: EmptyState(
                            title: 'No pickup tasks found',
                            message: 'Pickups scheduled for you will appear here.',
                            icon: Icons.inventory_2_outlined,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: deliveryPagePadding,
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return _PickupCard(
                                task: task,
                                onAccept: () => _accept(task),
                                onReject: () => _reject(task),
                                onArrive: () => _arrive(task),
                                onScan: () => _scanPackage(task),
                                onVerify: () => _verifyPickup(task),
                                onFail: () => _failPickup(task),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _PickupCard extends StatelessWidget {
  const _PickupCard({
    required this.task,
    required this.onAccept,
    required this.onReject,
    required this.onArrive,
    required this.onScan,
    required this.onVerify,
    required this.onFail,
  });

  final PickupTask task;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onArrive;
  final VoidCallback onScan;
  final VoidCallback onVerify;
  final VoidCallback onFail;

  @override
  Widget build(BuildContext context) {
    final statusColor = orderStatusColor(task.pickupStatus);
    final isAssigned = task.assignmentStatus == 'ASSIGNED';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.pickupNumber,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text('Order: ${task.orderNumber}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Tag(text: task.pickupStatus.replaceAll('_', ' '), color: statusColor),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 20, color: IndiBizzColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${task.pickupTown.isNotEmpty ? task.pickupTown : "Store hub"} · PIN ${task.pickupPincode}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Tag(text: '${task.packageCountExpected} packages expected', icon: Icons.inventory_2_outlined),
                const SizedBox(width: 8),
                if (task.scannedPackages > 0)
                  Tag(
                    text: '${task.scannedPackages} scanned',
                    icon: Icons.qr_code_2_rounded,
                    color: IndiBizzColors.success,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isAssigned && task.canAccept) ...[
                  ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Accept Pickup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(foregroundColor: IndiBizzColors.error),
                  ),
                ],
                if (task.assignmentStatus == 'ACCEPTED' && task.pickupStatus != 'ARRIVED')
                  ElevatedButton.icon(
                    onPressed: onArrive,
                    icon: const Icon(Icons.location_on_rounded, size: 16),
                    label: const Text('Arrived at Pickup'),
                  ),
                if (task.canScan)
                  OutlinedButton.icon(
                    onPressed: onScan,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                    label: const Text('Scan Package'),
                  ),
                if (task.canVerify) ...[
                  ElevatedButton.icon(
                    onPressed: onVerify,
                    icon: const Icon(Icons.verified_rounded, size: 16),
                    label: const Text('Verify Pickup (Enter OTP)'),
                    style: ElevatedButton.styleFrom(backgroundColor: IndiBizzColors.success, foregroundColor: Colors.white),
                  ),
                  OutlinedButton.icon(
                    onPressed: onFail,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
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
