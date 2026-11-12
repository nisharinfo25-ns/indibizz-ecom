import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui.dart';
import 'orders.dart';

class LogisticsPage extends StatefulWidget {
  const LogisticsPage({super.key, required this.repository});
  final OwnerRepository repository;

  @override
  State<LogisticsPage> createState() => _LogisticsPageState();
}

class _LogisticsPageState extends State<LogisticsPage> {
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
              values: const ['pickups', 'deliveries', 'people'],
              selected: const ['pickups', 'deliveries', 'people'][_tab],
              labelFor: (value) => switch (value) {
                'deliveries' => 'Deliveries',
                'people' => 'Delivery people',
                _ => 'Pickups',
              },
              onSelected: (value) => setState(() => _tab = switch (value) {
                    'deliveries' => 1,
                    'people' => 2,
                    _ => 0,
                  }),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _PickupsTab(repository: widget.repository),
              _DeliveriesTab(repository: widget.repository),
              _PersonnelTab(repository: widget.repository),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickupsTab extends StatefulWidget {
  const _PickupsTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_PickupsTab> createState() => _PickupsTabState();
}

class _PickupsTabState extends State<_PickupsTab> {
  String? _status;
  int _revision = 0;

  static const _statuses = <String?>[null, 'REQUESTED', 'ASSIGNED', 'ACCEPTED', 'ARRIVED', 'VERIFIED', 'CANCELLED'];

  Future<void> _assign(PickupListItem pickup) async {
    final personnel = await widget.repository.listDeliveryPersonnel();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Personnel>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PersonnelPicker(personnel: personnel, title: 'Assign ${pickup.pickupNumber}'),
    );
    if (selected == null || !mounted) return;
    String? reason;
    if (pickup.assignment != null && pickup.assignment!.staffUserId != selected.staffUserId) {
      reason = await askReason(
        context,
        title: 'Reassign pickup',
        hint: 'Why is this pickup being reassigned?',
        confirmLabel: 'Reassign',
      );
      if (reason == null || !mounted) return;
    }
    final ok = await runSellerAction(
      context,
      () => widget.repository.assignPickup(
        pickupId: pickup.id,
        staffUserId: selected.staffUserId,
        reason: reason ?? 'Manual assignment from the owner console.',
      ),
      success: 'Pickup assigned to ${selected.displayName}.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _cancel(PickupListItem pickup) async {
    final reason = await askReason(context, title: 'Cancel pickup', hint: 'Reason for cancelling this pickup request', confirmLabel: 'Cancel pickup');
    if (reason == null || !mounted) return;
    final ok = await runSellerAction(context, () => widget.repository.cancelPickup(pickup.id, reason), success: 'Pickup cancelled.');
    if (ok && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
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
        ),
        Expanded(
          child: OwnerAsyncPage<List<PickupListItem>>(
            key: ValueKey('pickups-$_revision'),
            scrollable: true,
            load: () => widget.repository.listPickups(status: _status),
            loadingLabel: 'Loading pickup requests…',
            emptyTitle: 'No pickups in this view',
            emptyMessage: 'Pickup requests are created from a packed order. They will appear here for assignment.',
            emptyIcon: Icons.local_shipping_outlined,
            isEmpty: (data) => data.isEmpty,
            builder: (context, pickups, refresh) => sellerList([
              Row(
                children: [
                  Expanded(child: Text('${pickups.length} pickup${pickups.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
                ],
              ),
              const SizedBox(height: 4),
              for (final pickup in pickups)
                OrderCardShell(
                  borderColor: pickup.status == 'REQUESTED' ? IndiBizzColors.warning : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(pickup.pickupNumber, style: Theme.of(context).textTheme.titleSmall)),
                          StatusBadge(status: pickup.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${pickup.orderNumber} • ${pickup.customerName} • ${pickup.townName} ${pickup.pincode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Tag(text: '${pickup.packageCountExpected} expected', icon: Icons.inventory_2_outlined),
                          Tag(text: '${pickup.scannedPackages} scanned', icon: Icons.qr_code_scanner_rounded),
                          Tag(text: '${pickup.packageCountVerified} verified', icon: Icons.verified_outlined),
                          if (pickup.assignment != null)
                            Tag(
                              text: '${pickup.assignment!.staffName ?? 'Assigned'}${pickup.assignment!.mode == 'AUTO' ? ' • auto' : ' • manual'}',
                              icon: Icons.person_outline_rounded,
                            ),
                        ],
                      ),
                      if (pickup.otp != null) ...[
                        const SizedBox(height: 9),
                        InlineNotice(
                          tone: StatusTone.pending,
                          title: 'Pickup OTP • ${pickup.otpExpiresAt == null ? 'active' : 'expires ${formatDateTime(pickup.otpExpiresAt)}'}',
                          message: pickup.otp!,
                          action: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => copyText(context, pickup.otp!, label: 'Pickup OTP'),
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: const Text('Copy OTP'),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (!const {'VERIFIED', 'CANCELLED'}.contains(pickup.status))
                            OutlinedButton.icon(
                              onPressed: () => _assign(pickup),
                              icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                              label: Text(pickup.assignment == null ? 'Assign' : 'Reassign'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 11)),
                            ),
                          if (pickup.shipmentId != null)
                            TextButton.icon(
                              onPressed: () => _generateManifest(pickup),
                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                              label: const Text('Manifest'),
                            ),
                          TextButton.icon(
                            onPressed: () => openAdminOrder(context, widget.repository, pickup.orderId),
                            icon: const Icon(Icons.receipt_long_outlined, size: 15),
                            label: const Text('Order'),
                          ),
                          if (const {'REQUESTED', 'ASSIGNED'}.contains(pickup.status))
                            TextButton.icon(
                              onPressed: () => _cancel(pickup),
                              icon: const Icon(Icons.cancel_outlined, size: 15),
                              label: const Text('Cancel'),
                              style: TextButton.styleFrom(foregroundColor: IndiBizzColors.danger),
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

  Future<void> _generateManifest(PickupListItem pickup) async {
    try {
      final result = await widget.repository.generateDocument(type: 'pickup_manifest', pickupId: pickup.id);
      final url = result['signed_url']?.toString();
      if (url == null || url.isEmpty) throw Exception('No download URL was returned.');
      final opened = await launchExternal(url);
      if (!opened) throw Exception('Could not open the pickup manifest.');
    } catch (error) {
      if (mounted) showToast(context, error.toString(), error: true);
    }
  }
}

class _DeliveriesTab extends StatefulWidget {
  const _DeliveriesTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_DeliveriesTab> createState() => _DeliveriesTabState();
}

class _DeliveriesTabState extends State<_DeliveriesTab> {
  String? _status;
  int _revision = 0;

  static const _statuses = <String?>[
    null,
    'CREATED',
    'READY_FOR_PICKUP',
    'PICKUP_REQUESTED',
    'PICKED_UP',
    'IN_TRANSIT',
    'ARRIVED_AT_DESTINATION',
    'OUT_FOR_DELIVERY',
    'DELIVERED',
    'DELIVERY_FAILED',
  ];

  Future<void> _assign(DeliveryListItem delivery) async {
    final personnel = await widget.repository.listDeliveryPersonnel();
    if (!mounted) return;
    final selected = await showModalBottomSheet<Personnel>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PersonnelPicker(personnel: personnel, title: 'Assign ${delivery.shipmentNumber}'),
    );
    if (selected == null || !mounted) return;
    String? reason;
    if (delivery.assignment != null && delivery.assignment!.staffUserId != selected.staffUserId) {
      reason = await askReason(context, title: 'Reassign delivery', hint: 'Why is this delivery being reassigned?', confirmLabel: 'Reassign');
      if (reason == null || !mounted) return;
    }
    final ok = await runSellerAction(
      context,
      () => widget.repository.assignDelivery(
        shipmentId: delivery.shipmentId,
        staffUserId: selected.staffUserId,
        reason: reason ?? 'Manual assignment from the owner console.',
      ),
      success: 'Delivery assigned to ${selected.displayName}.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _resetOtp(DeliveryListItem delivery) async {
    final ok = await confirmAction(
      context,
      title: 'Reset delivery OTP',
      message: 'Use this only when the customer cannot see their delivery OTP. The previous code stops working immediately.',
      confirmLabel: 'Reset OTP',
    );
    if (!ok || !mounted) return;
    final success = await runSellerAction(context, () => widget.repository.resetDeliveryOtp(delivery.shipmentId), success: 'Delivery OTP reset. The customer will see the new code in tracking.');
    if (success && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
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
        ),
        Expanded(
          child: OwnerAsyncPage<List<DeliveryListItem>>(
            key: ValueKey('deliveries-$_revision'),
            scrollable: true,
            load: () => widget.repository.listDeliveries(status: _status),
            loadingLabel: 'Loading shipments…',
            emptyTitle: 'No deliveries in this view',
            emptyMessage: 'Shipments become deliverable after a verified pickup.',
            emptyIcon: Icons.local_shipping_outlined,
            isEmpty: (data) => data.isEmpty,
            builder: (context, deliveries, refresh) => sellerList([
              Row(
                children: [
                  Expanded(child: Text('${deliveries.length} shipment${deliveries.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
                ],
              ),
              const SizedBox(height: 4),
              for (final delivery in deliveries)
                OrderCardShell(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(delivery.shipmentNumber, style: Theme.of(context).textTheme.titleSmall)),
                          StatusBadge(status: delivery.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${delivery.orderNumber} • ${delivery.customerName} • ${delivery.townName} ${delivery.pincode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Tag(text: '${delivery.packageCount} package${delivery.packageCount == 1 ? '' : 's'}', icon: Icons.inventory_2_outlined),
                          Tag(text: formatMoney(delivery.expectedCodPaise), icon: Icons.account_balance_wallet_outlined),
                          Tag(text: '${delivery.attempts} attempt${delivery.attempts == 1 ? '' : 's'}', icon: Icons.replay_rounded),
                          if (delivery.assignment != null)
                            Tag(text: delivery.assignment!.staffName ?? 'Assigned', icon: Icons.person_outline_rounded),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (const {'PICKED_UP', 'IN_TRANSIT', 'ARRIVED_AT_DESTINATION', 'DELIVERY_ATTEMPTED', 'CUSTOMER_UNAVAILABLE', 'SHIPMENT_DELAYED'}.contains(delivery.status))
                            OutlinedButton.icon(
                              onPressed: () => _assign(delivery),
                              icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                              label: Text(delivery.assignment == null ? 'Assign delivery' : 'Reassign'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 11)),
                            ),
                          if (const {'OUT_FOR_DELIVERY', 'DELIVERY_ATTEMPTED', 'CUSTOMER_UNAVAILABLE'}.contains(delivery.status))
                            TextButton.icon(
                              onPressed: () => _resetOtp(delivery),
                              icon: const Icon(Icons.password_rounded, size: 15),
                              label: const Text('Reset OTP'),
                            ),
                          TextButton.icon(
                            onPressed: () => openAdminOrder(context, widget.repository, delivery.orderId),
                            icon: const Icon(Icons.receipt_long_outlined, size: 15),
                            label: const Text('Order'),
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
}

class _PersonnelTab extends StatefulWidget {
  const _PersonnelTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_PersonnelTab> createState() => _PersonnelTabState();
}

class _PersonnelTabState extends State<_PersonnelTab> {
  int _revision = 0;

  Future<void> _edit(Personnel person) async {
    final name = await promptText(context, title: 'Edit staff profile', hint: 'Display name', initialValue: person.displayName);
    if (name == null || !mounted) return;
    final capacity = await promptText(
      context,
      title: 'Daily task capacity',
      hint: 'Tasks per day',
      initialValue: '${person.capacityPerDay == 0 ? 25 : person.capacityPerDay}',
      keyboardType: TextInputType.number,
      confirmLabel: 'Save profile',
    );
    if (capacity == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.updateStaffProfile(
        staffUserId: person.staffUserId,
        displayName: name,
        capacityPerDay: int.tryParse(capacity) ?? 25,
        employeeCode: person.employeeCode,
      ),
      success: 'Staff profile updated.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _suspend(Personnel person) async {
    final reason = await askReason(context, title: 'Suspend ${person.displayName}', hint: 'Reason for suspension', confirmLabel: 'Suspend');
    if (reason == null || !mounted) return;
    final ok = await runSellerAction(context, () => widget.repository.suspendDeliveryPerson(person.staffUserId, reason), success: '${person.displayName} suspended.');
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _reactivate(Personnel person) async {
    final ok = await runSellerAction(context, () => widget.repository.reactivateDeliveryPerson(person.staffUserId), success: '${person.displayName} reactivated.');
    if (ok && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAsyncPage<List<Personnel>>(
      key: ValueKey('personnel-$_revision'),
      scrollable: true,
      load: widget.repository.listDeliveryPersonnel,
      loadingLabel: 'Loading delivery people…',
      emptyTitle: 'No delivery people yet',
      emptyMessage: 'Invite own staff or an external partner from Team & partners.',
      emptyIcon: Icons.badge_outlined,
      isEmpty: (data) => data.isEmpty,
      builder: (context, personnel, refresh) => sellerList([
        Row(
          children: [
            Expanded(child: Text('${personnel.length} delivery person${personnel.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 4),
        for (final person in personnel)
          OrderCardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(name: person.displayName, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(person.displayName, style: Theme.of(context).textTheme.titleSmall)),
                              const SizedBox(width: 6),
                              StatusBadge(status: person.status),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${person.staffType == 'OWN' ? 'Own team' : 'Partner • ${person.partnerName ?? ''}'} • ${formatPhone(person.phone)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: person.isAvailable,
                      onChanged: person.status == 'ACTIVE'
                          ? (value) async {
                              final ok = await runSellerAction(
                                context,
                                () => widget.repository.setStaffAvailability(person.staffUserId, value),
                                success: value ? 'Marked available.' : 'Marked unavailable.',
                              );
                              if (ok && mounted) setState(() => _revision++);
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Tag(text: '${person.activeTasks}/${person.capacityPerDay == 0 ? '—' : person.capacityPerDay} active tasks', icon: Icons.work_outline_rounded),
                    Tag(text: person.coverageLabel.isEmpty ? 'No coverage' : person.coverageLabel, icon: Icons.map_outlined),
                    if (person.employeeCode != null && person.employeeCode!.isNotEmpty) Tag(text: person.employeeCode!, icon: Icons.badge_outlined),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (person.staffType == 'OWN')
                      TextButton.icon(onPressed: () => _edit(person), icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Edit profile')),
                    if (person.status == 'ACTIVE')
                      TextButton.icon(
                        onPressed: () => _suspend(person),
                        icon: const Icon(Icons.pause_circle_outline_rounded, size: 15),
                        label: const Text('Suspend'),
                        style: TextButton.styleFrom(foregroundColor: IndiBizzColors.danger),
                      )
                    else
                      TextButton.icon(onPressed: () => _reactivate(person), icon: const Icon(Icons.play_circle_outline_rounded, size: 15), label: const Text('Reactivate')),
                  ],
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

class _PersonnelPicker extends StatelessWidget {
  const _PersonnelPicker({required this.personnel, required this.title});
  final List<Personnel> personnel;
  final String title;

  @override
  Widget build(BuildContext context) {
    final active = personnel.where((person) => person.status == 'ACTIVE').toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Assignments are manual and override automatic scoring. The person is notified immediately.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          if (active.isEmpty)
            const EmptyView(
              title: 'No active delivery people',
              message: 'Reactivate a team member or create a staff invite first.',
              icon: Icons.person_off_outlined,
            )
          else
            for (final person in active)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  onTap: () => Navigator.pop(context, person),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      UserAvatar(name: person.displayName, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(person.displayName, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${person.staffType == 'OWN' ? 'Own team' : person.partnerName ?? 'Partner'} • ${person.activeTasks} active • ${person.isAvailable ? 'Available' : 'Unavailable'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (person.coverageLabel.isNotEmpty)
                              Text(person.coverageLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

Future<bool> launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
