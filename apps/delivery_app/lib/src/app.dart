import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import 'pages/cod.dart';
import 'pages/dashboard.dart';
import 'pages/deliveries.dart';
import 'pages/pickups.dart';
import 'pages/profile.dart';

class DeliveryConsole extends StatefulWidget {
  const DeliveryConsole({super.key, required this.profile, required this.auth});
  final Profile profile;
  final AuthController auth;

  @override
  State<DeliveryConsole> createState() => _DeliveryConsoleState();
}

class _DeliveryConsoleState extends State<DeliveryConsole> {
  late final StaffRepository _repository = StaffRepository(IndiBizz.client);
  int _selected = 0;

  static const _destinations = <ConsoleDestination>[
    ConsoleDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    ConsoleDestination(
      label: 'Deliveries',
      icon: Icons.local_shipping_outlined,
      selectedIcon: Icons.local_shipping_rounded,
    ),
    ConsoleDestination(
      label: 'Pickups',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    ConsoleDestination(
      label: 'COD & Cash',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
    ),
    ConsoleDestination(
      label: 'Profile & Alerts',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  static const _titles = <String, String>{
    'Dashboard': 'Delivery Console',
    'Deliveries': 'My Deliveries',
    'Pickups': 'My Pickups',
    'COD & Cash': 'Cash & Custody',
    'Profile & Alerts': 'Profile & Alerts',
  };

  static const _subtitles = <String, String>{
    'Dashboard': 'Shift overview and live delivery indicators.',
    'Deliveries': 'Navigate, verify OTP and deliver orders.',
    'Pickups': 'Collect packed shipments from seller hub.',
    'COD & Cash': 'Track cash custody and declare handovers.',
    'Profile & Alerts': 'Account details and assignment notices.',
  };

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(
        repository: _repository,
        onNavigate: (index) => setState(() => _selected = index),
      ),
      DeliveriesPage(repository: _repository),
      PickupsPage(repository: _repository),
      CodPage(repository: _repository),
      ProfilePage(
        profile: widget.profile,
        repository: _repository,
        onSignOut: widget.auth.signOut,
      ),
    ];

    final currentLabel = _destinations[_selected].label;

    return ConsoleShell(
      title: _titles[currentLabel]!,
      subtitle: _subtitles[currentLabel],
      roleLabel: widget.profile.role == 'PARTNER_ADMIN' ? 'Partner Admin' : 'Delivery Staff',
      profile: widget.profile,
      destinations: _destinations,
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() => _selected = index),
      onSignOut: widget.auth.signOut,
      body: IndexedStack(
        index: _selected,
        children: pages,
      ),
    );
  }
}
