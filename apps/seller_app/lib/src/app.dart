import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import 'pages/catalogue.dart';
import 'pages/cod.dart';
import 'pages/dashboard.dart';
import 'pages/logistics.dart';
import 'pages/orders.dart';
import 'pages/returns.dart';
import 'pages/settings.dart';
import 'pages/team.dart';

class SellerConsole extends StatefulWidget {
  const SellerConsole({super.key, required this.profile, required this.auth});
  final Profile profile;
  final AuthController auth;

  @override
  State<SellerConsole> createState() => _SellerConsoleState();
}

class _SellerConsoleState extends State<SellerConsole> {
  late final OwnerRepository _repository = OwnerRepository(IndiBizz.client);
  int _selected = 0;

  static const _destinations = <ConsoleDestination>[
    ConsoleDestination(label: 'Dashboard', icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded),
    ConsoleDestination(label: 'Orders', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded),
    ConsoleDestination(label: 'Catalogue', icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded),
    ConsoleDestination(label: 'Logistics', icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping_rounded),
    ConsoleDestination(label: 'COD & cash', icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet_rounded),
    ConsoleDestination(label: 'Returns', icon: Icons.assignment_return_outlined, selectedIcon: Icons.assignment_return_rounded),
    ConsoleDestination(label: 'Team & partners', icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded),
    ConsoleDestination(label: 'Settings & audit', icon: Icons.tune_outlined, selectedIcon: Icons.tune_rounded),
  ];

  static const _titles = <String, String>{
    'Dashboard': 'Store overview',
    'Orders': 'Orders',
    'Catalogue': 'Catalogue & stock',
    'Logistics': 'Pickups & deliveries',
    'COD & cash': 'COD & cash',
    'Returns': 'Returns',
    'Team & partners': 'Team & partners',
    'Settings & audit': 'Settings & audit',
  };

  static const _subtitles = <String, String>{
    'Dashboard': 'Live COD commerce, packing and dispatch signals.',
    'Orders': 'Approve, pack and dispatch every customer order.',
    'Catalogue': 'Products, categories and immutable stock movements.',
    'Logistics': 'Assign work, share pickup OTPs and monitor delivery.',
    'COD & cash': 'Reconcile every rupee collected in the field.',
    'Returns': 'Decide, receive and close customer returns.',
    'Team & partners': 'Invite staff, manage partners, towns and PIN codes.',
    'Settings & audit': 'Business identity, policies, assignment and audit trail.',
  };

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(repository: _repository, ownerName: widget.profile.fullName, onNavigate: (index) => setState(() => _selected = index)),
      OrdersPage(repository: _repository),
      CataloguePage(repository: _repository),
      LogisticsPage(repository: _repository),
      CodPage(repository: _repository),
      ReturnsPage(repository: _repository),
      TeamPage(repository: _repository),
      SettingsPage(repository: _repository, profile: widget.profile),
    ];
    final title = _titles[_destinations[_selected].label]!;
    return ConsoleShell(
      title: title,
      subtitle: _subtitles[_destinations[_selected].label],
      roleLabel: 'Owner',
      profile: widget.profile,
      destinations: _destinations,
      selectedIndex: _selected,
      onDestinationSelected: (index) => setState(() => _selected = index),
      onSignOut: widget.auth.signOut,
      body: IndexedStack(index: _selected, children: pages),
    );
  }
}
