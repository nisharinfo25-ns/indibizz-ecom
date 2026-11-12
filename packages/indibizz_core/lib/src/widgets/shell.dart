import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/order_status.dart';
import 'common.dart';

class ConsoleDestination {
  const ConsoleDestination({required this.label, required this.icon, required this.selectedIcon});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, required this.controller});
  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => controller.toggle(Theme.of(context).brightness),
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20),
    );
  }
}

/// Shared responsive console used by the seller and delivery applications.
/// Wide layouts get a permanent navy-edged navigation panel; phones get a
/// drawer. The account block is always local to the navigation panel so the
/// main workspace stays uncluttered.
class ConsoleShell extends StatelessWidget {
  const ConsoleShell({
    super.key,
    required this.title,
    required this.roleLabel,
    required this.profile,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSignOut,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
    this.headerTrailing,
  });

  final String title;
  final String? subtitle;
  final String roleLabel;
  final Profile profile;
  final List<ConsoleDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSignOut;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 920;
    if (narrow) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 4,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(compact: true),
              const SizedBox(width: 10),
              Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            ...actions,
            ThemeToggleButton(controller: ThemeController.instance),
            const SizedBox(width: 4),
          ],
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Open navigation',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
        ),
        drawer: Drawer(
          width: 286,
          child: SafeArea(
            child: _NavigationPanel(
              title: title,
              roleLabel: roleLabel,
              profile: profile,
              destinations: destinations,
              selectedIndex: selectedIndex,
              onSelected: (index) {
                Navigator.of(context).pop();
                onDestinationSelected(index);
              },
              onSignOut: onSignOut,
              includeBrandHeader: true,
            ),
          ),
        ),
        floatingActionButton: floatingActionButton,
        body: SafeArea(child: body),
      );
    }

    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 252,
            child: Material(
              color: Theme.of(context).brightness == Brightness.dark
                  ? IndiBizzColors.darkSurface
                  : IndiBizzColors.surface,
              child: _NavigationPanel(
                title: title,
                roleLabel: roleLabel,
                profile: profile,
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onDestinationSelected,
                onSignOut: onSignOut,
                includeBrandHeader: true,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 20, 22, 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? IndiBizzColors.darkBorder
                            : IndiBizzColors.border,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: Theme.of(context).textTheme.headlineSmall),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                      if (headerTrailing != null) ...[headerTrailing!, const SizedBox(width: 8)],
                      ...actions,
                      ThemeToggleButton(controller: ThemeController.instance),
                    ],
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1260),
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.title,
    required this.roleLabel,
    required this.profile,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSignOut,
    required this.includeBrandHeader,
  });

  final String title;
  final String roleLabel;
  final Profile profile;
  final List<ConsoleDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;
  final bool includeBrandHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        if (includeBrandHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
            child: Align(alignment: Alignment.centerLeft, child: const BrandMark()),
          ),
        if (includeBrandHeader)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.border),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            children: [
              for (var index = 0; index < destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _NavItem(
                    destination: destinations[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    UserAvatar(name: profile.fullName, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(roleLabel, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});
  final ConsoleDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selectedColor = dark ? const Color(0xFF9CC0FF) : IndiBizzColors.navy;
    return Material(
      color: selected ? (dark ? const Color(0xFF1A3049) : const Color(0xFFEEF2F7)) : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 19,
                color: selected ? selectedColor : theme.textTheme.bodySmall?.color,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  destination.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? selectedColor : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: selectedColor, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the compile-time Supabase configuration is absent. The app must
/// never pretend that authentication is available.
class SetupNotice extends StatelessWidget {
  const SetupNotice({
    super.key,
    required this.appName,
    required this.roleLabel,
    required this.error,
  });

  final String appName;
  final String roleLabel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 28),
                  Text('$appName setup', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'This build is not connected to the IndiaBizz Supabase project yet. '
                    'Nothing is simulated: sign-in and live data stay disabled until credentials are supplied.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const StatusBadge(status: 'SETUP_REQUIRED'),
                        const SizedBox(height: 14),
                        Text('Run with real project credentials', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        SelectableText(
                          'flutter run \\\n'
                          '  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \\\n'
                          '  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            height: 1.6,
                            color: dark ? IndiBizzColors.darkInk : IndiBizzColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Use only the anon (publishable) key in a client build. Never embed the service-role key.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InlineNotice(
                    tone: StatusTone.muted,
                    title: roleLabel,
                    message: error ?? 'Set SUPABASE_URL and SUPABASE_ANON_KEY, then rebuild this application.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
