import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.profile,
    required this.repository,
    required this.onSignOut,
  });

  final Profile profile;
  final CustomerRepository repository;
  final VoidCallback onSignOut;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late Profile _profile = widget.profile;
  List<Address> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await widget.repository.getProfile();
      final addrs = await widget.repository.getAddresses();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _addresses = addrs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _profile.fullName);
    final emailCtrl = TextEditingController(text: _profile.email ?? '');

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address (Optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop(true);
              final ok = await runCustomerAction(
                this.context,
                () => widget.repository.updateProfile(
                  fullName: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                ),
                success: 'Profile updated.',
              );
              if (ok) _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: customerPagePadding,
      children: [
        // Profile Info Card
        SurfaceCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: IndiBizzColors.primary.withValues(alpha: 0.1),
                child: Text(
                  _profile.fullName.isNotEmpty ? _profile.fullName[0].toUpperCase() : 'C',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: IndiBizzColors.primary),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_profile.fullName.isNotEmpty ? _profile.fullName : 'Valued Customer',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(_profile.phone ?? 'No phone registered', style: Theme.of(context).textTheme.bodySmall),
                    if (_profile.email != null && _profile.email!.isNotEmpty)
                      Text(_profile.email!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit Profile',
                onPressed: _editProfile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Saved Addresses
        Text('Saved Delivery Addresses', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_loading && _addresses.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (_addresses.isEmpty)
          const SurfaceCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('No saved addresses yet. Add one during checkout.')),
            ),
          )
        else
          ..._addresses.map((addr) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(addr.recipientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: IndiBizzColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(addr.label, style: const TextStyle(fontSize: 11, color: IndiBizzColors.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${addr.line1}${addr.line2.isNotEmpty ? ", " + addr.line2 : ""}'),
                    Text('PIN: ${addr.pincode} · Contact: ${addr.phone}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 24),

        // Sign Out
        SurfaceCard(
          child: ListTile(
            leading: const Icon(Icons.logout_rounded, color: IndiBizzColors.error),
            title: const Text('Sign Out', style: TextStyle(color: IndiBizzColors.error, fontWeight: FontWeight.bold)),
            onTap: () async {
              final ok = await confirmAction(
                context,
                title: 'Sign out?',
                message: 'You can sign back in anytime with your mobile number and OTP.',
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
