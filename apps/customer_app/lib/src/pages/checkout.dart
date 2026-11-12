import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.repository,
    required this.onOrderPlaced,
  });

  final CustomerRepository repository;
  final ValueChanged<String> onOrderPlaced;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  List<Address> _addresses = [];
  Address? _selectedAddress;
  Quote? _quote;
  bool _loading = true;
  bool _quoting = false;
  bool _placing = false;
  Object? _error;
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.getAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = list;
        if (list.isNotEmpty) {
          _selectedAddress = list.first;
        }
        _loading = false;
      });
      if (_selectedAddress != null) {
        await _fetchQuote(_selectedAddress!.id);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  Future<void> _fetchQuote(String addressId) async {
    setState(() => _quoting = true);
    try {
      final quote = await widget.repository.quote(addressId);
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoting = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _quoting = false);
      showToast(context, cleanErrorMessage(err), error: true);
    }
  }

  Future<void> _addNewAddress() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final line1Ctrl = TextEditingController();
    final line2Ctrl = TextEditingController();
    final pinCtrl = TextEditingController();
    Town? selectedTown;
    List<Town> towns = [];
    String? serviceabilityMessage;
    bool isServiceable = false;
    bool checkingPin = false;

    try {
      towns = await widget.repository.getTowns();
      if (towns.isNotEmpty) selectedTown = towns.first;
    } catch (_) {}

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 10,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add Delivery Address', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full Recipient Name *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Phone Number (+91) *',
                      hintText: '+919876543210',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: line1Ctrl,
                    decoration: const InputDecoration(labelText: 'House / Flat / Street *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: line2Ctrl,
                    decoration: const InputDecoration(labelText: 'Area / Colony (Optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  if (towns.isNotEmpty)
                    DropdownButtonFormField<Town>(
                      value: selectedTown,
                      decoration: const InputDecoration(labelText: 'Serviceable Town *', border: OutlineInputBorder()),
                      items: towns.map((t) => DropdownMenuItem(value: t, child: Text('${t.name}, ${t.district}'))).toList(),
                      onChanged: (val) {
                        setSheetState(() => selectedTown = val);
                      },
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pinCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: '6-digit PIN Code *',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) async {
                            if (val.trim().length == 6) {
                              setSheetState(() => checkingPin = true);
                              try {
                                final s = await widget.repository.checkServiceability(val.trim(), townId: selectedTown?.id);
                                setSheetState(() {
                                  isServiceable = s.serviceable;
                                  serviceabilityMessage = s.serviceable
                                      ? 'Delivery available via ${s.deliveryMode ?? "standard route"}'
                                      : 'PIN code not currently serviceable';
                                  checkingPin = false;
                                });
                              } catch (_) {
                                setSheetState(() {
                                  isServiceable = false;
                                  serviceabilityMessage = 'PIN check failed';
                                  checkingPin = false;
                                });
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (checkingPin)
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      else if (serviceabilityMessage != null)
                        Expanded(
                          child: Text(
                            serviceabilityMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isServiceable ? IndiBizzColors.success : IndiBizzColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        final line1 = line1Ctrl.text.trim();
                        final pin = pinCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty || line1.isEmpty || pin.length != 6 || selectedTown == null) {
                          showToast(sheetContext, 'Please fill all required fields and verify PIN code.', error: true);
                          return;
                        }
                        try {
                          await widget.repository.client.rpc('create_address', params: {
                            'p_label': 'Home',
                            'p_recipient_name': name,
                            'p_phone': phone.startsWith('+') ? phone : '+91$phone',
                            'p_line1': line1,
                            'p_line2': line2Ctrl.text.trim().isNotEmpty ? line2Ctrl.text.trim() : null,
                            'p_town_id': selectedTown!.id,
                            'p_pincode': pin,
                            'p_is_default': true,
                          });
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
                        } catch (e) {
                          showToast(sheetContext, cleanErrorMessage(e), error: true);
                        }
                      },
                      child: const Text('Save & Use Address'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (created == true) {
      await _loadAddresses();
    }
  }

  Future<void> _placeOrder() async {
    if (_selectedAddress == null) {
      showToast(context, 'Please select or add a delivery address.', error: true);
      return;
    }

    setState(() => _placing = true);
    try {
      final res = await widget.repository.placeOrder(
        addressId: _selectedAddress!.id,
        note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
      );
      final orderId = res['order_id']?.toString() ?? '';
      final orderNumber = res['order_number']?.toString() ?? 'Order';

      if (!mounted) return;
      setState(() => _placing = false);

      widget.onOrderPlaced(orderId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order $orderNumber placed successfully!'),
          backgroundColor: IndiBizzColors.success,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _placing = false);
      showToast(context, cleanErrorMessage(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: LoadingView(label: 'Preparing checkout…')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: customerPagePadding,
        children: [
          // Address Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Delivery Address', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _addNewAddress,
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text('Add New'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_addresses.isEmpty)
            SurfaceCard(
              child: Column(
                children: [
                  const Text('No saved delivery address found.'),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _addNewAddress, child: const Text('Add Delivery Address')),
                ],
              ),
            )
          else
            ..._addresses.map((addr) {
              final isSelected = _selectedAddress?.id == addr.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  color: isSelected ? IndiBizzColors.primary.withValues(alpha: 0.05) : null,
                  child: RadioListTile<Address>(
                    value: addr,
                    groupValue: _selectedAddress,
                    contentPadding: EdgeInsets.zero,
                    title: Text(addr.recipientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${addr.line1}${addr.line2.isNotEmpty ? ", " + addr.line2 : ""}'),
                        Text('Phone: ${addr.phone} · PIN: ${addr.pincode}'),
                      ],
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedAddress = val);
                        _fetchQuote(val.id);
                      }
                    },
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // Payment Method: Cash on Delivery
          Text('Payment Method', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SurfaceCard(
            child: Row(
              children: [
                const Icon(Icons.payments_rounded, color: IndiBizzColors.success, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cash on Delivery (COD)', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'Pay with cash at your doorstep upon receiving your package and verifying the delivery OTP.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_rounded, color: IndiBizzColors.success),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Delivery Note
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Delivery Instructions (Optional)',
              hintText: 'Leave with neighbour, call upon arrival, etc.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Order Quote Summary
          Text('Order Summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_quoting)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_quote != null)
            SurfaceCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Items Subtotal'),
                      Text(formatMoney(_quote!.subtotalPaise)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Estimated Delivery Fee'),
                      Text(_quote!.shippingPaise > 0 ? formatMoney(_quote!.shippingPaise) : 'FREE'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Taxes'),
                      Text(_quote!.taxPaise > 0 ? formatMoney(_quote!.taxPaise) : 'Included'),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Payable (COD)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        formatMoney(_quote!.totalPaise),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: IndiBizzColors.primary,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // Place Order Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _placing || _selectedAddress == null || _quote == null ? null : _placeOrder,
              icon: const Icon(Icons.lock_rounded),
              label: Text(_placing ? 'Placing Order…' : 'Confirm & Place COD Order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: IndiBizzColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
