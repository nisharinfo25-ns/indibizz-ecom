import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    required this.onNavigate,
  });

  final StaffRepository repository;
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  StaffDashboard? _dashboard;
  bool _loading = true;
  Object? _error;
  bool _togglingAvailability = false;

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
      final dash = await widget.repository.dashboard();
      if (!mounted) return;
      setState(() {
        _dashboard = dash;
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

  Future<void> _toggleAvailability(bool current) async {
    setState(() => _togglingAvailability = true);
    final target = !current;
    final ok = await runStaffAction(
      context,
      () => widget.repository.setAvailability(target),
      success: target ? 'You are now online & available for tasks.' : 'You are now offline.',
    );
    if (ok) {
      await _load();
    }
    if (mounted) setState(() => _togglingAvailability = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _dashboard == null) {
      return const Center(child: LoadingView(label: 'Loading delivery dashboard…'));
    }
    if (_error != null && _dashboard == null) {
      return ErrorNotice(
        title: 'Could not load delivery dashboard',
        error: _error.toString(),
        onRetry: _load,
      );
    }
    final d = _dashboard!;
    final isOnline = d.staff.isAvailable;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: deliveryPagePadding,
        children: [
          // Duty status banner
          SurfaceCard(
            color: isOnline
                ? IndiBizzColors.success.withValues(alpha: 0.08)
                : IndiBizzColors.neutral300.withValues(alpha: 0.15),
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded,
                  color: isOnline ? IndiBizzColors.success : IndiBizzColors.neutral500,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnline ? 'On Duty — Online' : 'Off Duty — Offline',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isOnline ? IndiBizzColors.success : null,
                            ),
                      ),
                      Text(
                        isOnline
                            ? 'Ready to receive pickup & delivery assignments.'
                            : 'Set yourself online when ready to deliver.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _togglingAvailability ? null : () => _toggleAvailability(isOnline),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOnline ? IndiBizzColors.error : IndiBizzColors.success,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isOnline ? 'Go Offline' : 'Go Online'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Active tasks overview
          Text('Today\'s Overview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.35,
                children: [
                  MetricCard(
                    label: 'Active Deliveries',
                    value: '${d.activeDeliveries}',
                    subtitle: '${d.deliveriesCompletedToday} delivered today',
                    icon: Icons.delivery_dining_rounded,
                  ),
                  MetricCard(
                    label: 'Active Pickups',
                    value: '${d.activePickups}',
                    subtitle: '${d.pickupsCompletedToday} picked up today',
                    icon: Icons.inventory_2_rounded,
                  ),
                  MetricCard(
                    label: 'Cash in Custody',
                    value: formatMoney(d.cashInCustodyPaise),
                    subtitle: 'Must be deposited',
                    icon: Icons.payments_rounded,
                  ),
                  MetricCard(
                    label: 'COD Collected Today',
                    value: formatMoney(d.codCollectedTodayPaise),
                    subtitle: 'Total field collection',
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Quick actions
          Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onNavigate(1), // Deliveries
                  icon: const Icon(Icons.local_shipping_rounded),
                  label: const Text('My Deliveries'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onNavigate(2), // Pickups
                  icon: const Icon(Icons.inventory_rounded),
                  label: const Text('My Pickups'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onNavigate(3), // COD
                  icon: const Icon(Icons.currency_rupee_rounded),
                  label: const Text('Cash Handover'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Staff identity detail
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vehicle & Shift Details', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vehicle', style: Theme.of(context).textTheme.bodySmall),
                          Text('${d.staff.vehicleType ?? "Not registered"} · ${d.staff.vehicleNumber ?? "-"}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Employee Code', style: Theme.of(context).textTheme.bodySmall),
                          Text(d.staff.employeeCode ?? 'Direct staff',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
