import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';
import 'orders.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.repository, required this.ownerName, required this.onNavigate});
  final OwnerRepository repository;
  final String ownerName;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return OwnerAsyncPage<OwnerDashboard>(
      load: repository.dashboard,
      loadingLabel: 'Reading today’s store activity…',
      emptyTitle: 'Your store starts here',
      emptyMessage: 'Approve your first order to see live commerce and dispatch signals.',
      emptyIcon: Icons.storefront_outlined,
      isEmpty: (data) => data.recentOrders.isEmpty && data.ordersToday == 0,
      builder: (context, data, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TodayHero(data: data, ownerName: ownerName),
          const SizedBox(height: 14),
          if (data.pendingApproval > 0) ...[
            InlineNotice(
              tone: StatusTone.pending,
              title: '${data.pendingApproval} order${data.pendingApproval == 1 ? '' : 's'} waiting for approval',
              message: 'Approve only when stock and the delivery address are verified. Stock is reserved, not reduced, until approval.',
              action: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => onNavigate(1),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                  label: const Text('Review orders'),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final tileWidth = width >= 1040
                  ? (width - 36) / 4
                  : width >= 620
                      ? (width - 12) / 2
                      : width;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: MetricTile(
                      label: 'Ready for pickup',
                      value: '${data.readyForPickup}',
                      caption: '${data.packagesWaitingPickup} packages waiting',
                      icon: Icons.inventory_rounded,
                      tone: StatusTone.info,
                      onTap: () => onNavigate(3),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: MetricTile(
                      label: 'Out for delivery',
                      value: '${data.outForDelivery}',
                      caption: '${data.pickupsInProgress} pickups in progress',
                      icon: Icons.local_shipping_rounded,
                      tone: StatusTone.pending,
                      onTap: () => onNavigate(3),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: MetricTile(
                      label: 'Delivered today',
                      value: '${data.deliveredToday}',
                      caption: formatMoney(data.deliveredValueTodayPaise),
                      icon: Icons.task_alt_rounded,
                      tone: StatusTone.success,
                      onTap: () => onNavigate(1),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: MetricTile(
                      label: 'COD to verify',
                      value: formatMoneyCompact(data.codPendingVerificationPaise),
                      caption: '${data.pendingReturns} returns pending',
                      icon: Icons.account_balance_wallet_rounded,
                      tone: data.codPendingVerificationPaise > 0 ? StatusTone.pending : StatusTone.muted,
                      onTap: () => onNavigate(4),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final orders = _RecentOrders(data: data, onOpen: (id) => openAdminOrder(context, repository, id).then((_) => refresh()));
              final activity = _RecentActivity(activities: data.recentActivity);
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [orders, const SizedBox(height: 14), activity],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: orders),
                  const SizedBox(width: 14),
                  Expanded(flex: 4, child: activity),
                ],
              );
            },
          ),
          if (data.lowStockProducts > 0) ...[
            const SizedBox(height: 14),
            InlineNotice(
              tone: StatusTone.danger,
              title: '${data.lowStockProducts} active product${data.lowStockProducts == 1 ? '' : 's'} low on stock',
              message: 'Restock before accepting new COD orders. ${data.activeProducts} products are currently active.',
              action: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => onNavigate(2),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('Open stock'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.data, required this.ownerName});
  final OwnerDashboard data;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final firstName = ownerName.trim().split(RegExp(r'\s+')).first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1F3A), Color(0xFF14345B), Color(0xFF08182C)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -42,
            top: -62,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle, color: IndiBizzColors.gold.withValues(alpha: 0.14)),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, $firstName.',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
              ),
              const SizedBox(height: 6),
              Text(
                '${data.ordersToday} order${data.ordersToday == 1 ? '' : 's'} placed today • ₹${formatMoney(data.deliveredValueTodayPaise, withSymbol: false)} delivered',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 26,
                runSpacing: 14,
                children: [
                  _HeroStat(label: 'To approve', value: '${data.pendingApproval}'),
                  _HeroStat(label: 'To pack', value: '${data.activeProducts} active SKUs'),
                  _HeroStat(label: 'Cash in field', value: formatMoneyCompact(data.codPendingVerificationPaise)),
                  _HeroStat(label: 'Unread alerts', value: '${data.unreadNotifications}'),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'All times shown in ${data.timezone}.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10.5, letterSpacing: 0.2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      ],
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.data, required this.onOpen});
  final OwnerDashboard data;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return DetailSection(
      title: 'Recent orders',
      trailing: Text('${data.recentOrders.length} latest', style: Theme.of(context).textTheme.bodySmall),
      child: data.recentOrders.isEmpty
          ? Text('No orders have been placed yet.', style: Theme.of(context).textTheme.bodySmall)
          : Column(
              children: [
                for (final order in data.recentOrders) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(order.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
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
                                const SizedBox(height: 3),
                                Text(
                                  '${order.customerName} • ${order.itemCount} item${order.itemCount == 1 ? '' : 's'}${order.townName.isEmpty ? '' : ' • ${order.townName}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyText(paise: order.totalPaise, size: 13),
                              Text(relativeTime(order.createdAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (order != data.recentOrders.last)
                    Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.6)),
                ],
              ],
            ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.activities});
  final List<RecentActivity> activities;

  @override
  Widget build(BuildContext context) {
    return DetailSection(
      title: 'Live dispatch activity',
      child: activities.isEmpty
          ? Text('Dispatch events will appear here after the first pickup.', style: Theme.of(context).textTheme.bodySmall)
          : Column(
              children: [
                for (final activity in activities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                            color: toneColor(statusTone(activity.eventType)),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(statusLabel(activity.eventType), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12)),
                              Text(
                                '${activity.orderNumber}${activity.shipmentNumber.isEmpty ? '' : ' • ${activity.shipmentNumber}'}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        Text(relativeTime(activity.createdAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
