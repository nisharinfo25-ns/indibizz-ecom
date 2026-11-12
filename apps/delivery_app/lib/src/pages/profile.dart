import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.profile,
    required this.repository,
    required this.onSignOut,
  });

  final Profile profile;
  final StaffRepository repository;
  final VoidCallback onSignOut;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<NotificationItem> _notifications = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.listNotifications(limit: 40);
      if (!mounted) return;
      setState(() {
        _notifications = list;
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

  Future<void> _markRead(NotificationItem item) async {
    if (item.readAt != null) return;
    try {
      await widget.repository.markNotificationRead(item.id);
      await _loadNotifications();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: deliveryPagePadding,
      children: [
        // Staff Profile header
        SurfaceCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: IndiBizzColors.primary.withValues(alpha: 0.1),
                child: Text(
                  widget.profile.fullName.isNotEmpty
                      ? widget.profile.fullName.substring(0, 1).toUpperCase()
                      : 'D',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: IndiBizzColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.profile.fullName.isNotEmpty ? widget.profile.fullName : 'Delivery Partner',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.profile.phone ?? 'No phone registered',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Tag(
                      text: widget.profile.role.replaceAll('_', ' '),
                      color: IndiBizzColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Notifications Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Notifications & Alerts', style: Theme.of(context).textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Refresh notifications',
              onPressed: _loadNotifications,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_loading && _notifications.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: LoadingView(label: 'Checking notifications…')))
        else if (_error != null && _notifications.isEmpty)
          ErrorNotice(title: 'Could not load alerts', error: _error.toString(), onRetry: _loadNotifications)
        else if (_notifications.isEmpty)
          const SurfaceCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No notifications received yet.')),
            ),
          )
        else
          ..._notifications.map((item) {
            final isUnread = item.readAt == null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                color: isUnread ? IndiBizzColors.primary.withValues(alpha: 0.05) : null,
                child: InkWell(
                  onTap: () => _markRead(item),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isUnread ? Icons.mark_email_unread_rounded : Icons.mark_email_read_outlined,
                        color: isUnread ? IndiBizzColors.primary : IndiBizzColors.neutral400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(item.body, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              formatDate(item.createdAt),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: IndiBizzColors.neutral500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 28),

        // Sign Out Button
        SurfaceCard(
          child: ListTile(
            leading: const Icon(Icons.logout_rounded, color: IndiBizzColors.error),
            title: const Text('Sign Out', style: TextStyle(color: IndiBizzColors.error, fontWeight: FontWeight.bold)),
            subtitle: const Text('End your shift session'),
            onTap: () async {
              final ok = await confirmAction(
                context,
                title: 'Sign out of delivery app?',
                message: 'Make sure any collected cash has been declared if you are ending your shift.',
                confirmLabel: 'Sign Out',
                isDestructive: true,
              );
              if (ok) widget.onSignOut();
            },
          ),
        ),
      ],
    );
  }
}
