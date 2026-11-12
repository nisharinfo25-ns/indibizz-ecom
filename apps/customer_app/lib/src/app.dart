import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import 'pages/account.dart';
import 'pages/cart.dart';
import 'pages/checkout.dart';
import 'pages/home.dart';
import 'pages/orders.dart';

class CustomerConsole extends StatefulWidget {
  const CustomerConsole({super.key, required this.profile, required this.auth});
  final Profile profile;
  final AuthController auth;

  @override
  State<CustomerConsole> createState() => _CustomerConsoleState();
}

class _CustomerConsoleState extends State<CustomerConsole> {
  late final CustomerRepository _repository = CustomerRepository(IndiBizz.client);
  int _selected = 0;

  void _navigateToCheckout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          repository: _repository,
          onOrderPlaced: (orderId) {
            Navigator.of(context).pop(); // pop checkout
            setState(() => _selected = 2); // switch to Orders tab
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        repository: _repository,
        onNavigateToCart: () => setState(() => _selected = 1),
      ),
      CartPage(
        repository: _repository,
        onNavigateToShop: () => setState(() => _selected = 0),
        onNavigateToCheckout: _navigateToCheckout,
      ),
      OrdersPage(
        repository: _repository,
        onNavigateToShop: () => setState(() => _selected = 0),
      ),
      AccountPage(
        profile: widget.profile,
        repository: _repository,
        onSignOut: widget.auth.signOut,
      ),
    ];

    const titles = ['IndiaBizz Store', 'My Cart', 'My Orders', 'Account'];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(compact: true),
            const SizedBox(width: 8),
            Text(titles[_selected]),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () => ThemeController.instance.toggle(Theme.of(context).brightness),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selected,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (idx) => setState(() => _selected = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'Shop',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag_rounded),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
