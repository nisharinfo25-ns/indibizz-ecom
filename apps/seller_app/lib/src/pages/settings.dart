import 'dart:convert';

import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.repository, required this.profile});
  final OwnerRepository repository;
  final Profile profile;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _tab = 0;

  static const _tabs = ['business', 'commerce', 'logistics', 'audit'];
  static const _labels = ['Business', 'Commerce & policy', 'Logistics', 'Audit trail'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChipRow(
              values: _tabs,
              selected: _tabs[_tab],
              labelFor: (value) => _labels[_tabs.indexOf(value!)],
              onSelected: (value) => setState(() => _tab = _tabs.indexOf(value!)),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _SettingsLoader(repository: widget.repository, section: _SettingsSection.business),
              _SettingsLoader(repository: widget.repository, section: _SettingsSection.commerce),
              _SettingsLoader(repository: widget.repository, section: _SettingsSection.logistics),
              _AuditTab(repository: widget.repository),
            ],
          ),
        ),
      ],
    );
  }
}

enum _SettingsSection { business, commerce, logistics }

class _SettingsData {
  const _SettingsData(this.settings, this.towns);
  final OwnerSettings settings;
  final List<AdminTown> towns;
}

class _SettingsLoader extends StatefulWidget {
  const _SettingsLoader({required this.repository, required this.section});
  final OwnerRepository repository;
  final _SettingsSection section;

  @override
  State<_SettingsLoader> createState() => _SettingsLoaderState();
}

class _SettingsLoaderState extends State<_SettingsLoader> {
  _SettingsData? _data;
  Object? _error;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.getSettings(),
        widget.repository.listTowns(),
      ]);
      if (!mounted) return;
      setState(() => _data = _SettingsData(results[0] as OwnerSettings, results[1] as List<AdminTown>));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _saved(OwnerSettings settings) {
    if (!mounted) return;
    setState(() {
      _data = _SettingsData(settings, _data?.towns ?? const []);
      _revision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SingleChildScrollView(
        padding: sellerPagePadding,
        child: ErrorView(error: _error!, onRetry: _load),
      );
    }
    final data = _data;
    if (data == null) {
      return const Padding(padding: sellerPagePadding, child: LoadingView(label: 'Loading store settings…'));
    }
    final key = ValueKey('${widget.section.name}-$_revision');
    return switch (widget.section) {
      _SettingsSection.business => _BusinessForm(key: key, repository: widget.repository, data: data, onSaved: _saved),
      _SettingsSection.commerce => _CommercePolicyForm(key: key, repository: widget.repository, data: data, onSaved: _saved),
      _SettingsSection.logistics => _LogisticsForm(key: key, repository: widget.repository, data: data, onSaved: _saved),
    };
  }
}

String _string(Map<String, dynamic> map, String key, [String fallback = '']) {
  final value = map[key];
  return value == null ? fallback : value.toString();
}

bool _bool(Map<String, dynamic> map, String key, [bool fallback = false]) {
  final value = map[key];
  return value is bool ? value : fallback;
}

int _int(Map<String, dynamic> map, String key, [int fallback = 0]) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _double(Map<String, dynamic> map, String key, [double fallback = 0]) {
  final value = map[key];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

// ---------------------------------------------------------------------------
// Business
// ---------------------------------------------------------------------------
class _BusinessForm extends StatefulWidget {
  const _BusinessForm({super.key, required this.repository, required this.data, required this.onSaved});
  final OwnerRepository repository;
  final _SettingsData data;
  final ValueChanged<OwnerSettings> onSaved;

  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  final _formKey = GlobalKey<FormState>();
  late final _legalName = TextEditingController(text: _string(widget.data.settings.business, 'legal_name'));
  late final _displayName = TextEditingController(text: _string(widget.data.settings.business, 'display_name', 'IndiaBizz'));
  late final _address = TextEditingController(text: _string(widget.data.settings.business, 'address'));
  late final _phone = TextEditingController(text: _string(widget.data.settings.business, 'phone'));
  late final _email = TextEditingController(text: _string(widget.data.settings.business, 'email'));
  late final _gstin = TextEditingController(text: _string(widget.data.settings.business, 'gstin'));
  late final _supportPhone = TextEditingController(text: _string(widget.data.settings.business, 'support_phone'));
  late final _supportEmail = TextEditingController(text: _string(widget.data.settings.business, 'support_email'));
  late final _timezone = TextEditingController(text: _string(widget.data.settings.business, 'timezone', 'Asia/Kolkata'));
  late final _invoiceTerms = TextEditingController(text: _string(widget.data.settings.business, 'invoice_terms'));
  late final _pickupPincode = TextEditingController(text: _string(widget.data.settings.business, 'pickup_pincode'));
  String? _pickupTownId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final stored = _string(widget.data.settings.business, 'pickup_town_id');
    _pickupTownId = widget.data.towns.any((town) => town.id == stored) ? stored : null;
  }

  @override
  void dispose() {
    for (final controller in [
      _legalName,
      _displayName,
      _address,
      _phone,
      _email,
      _gstin,
      _supportPhone,
      _supportEmail,
      _timezone,
      _invoiceTerms,
      _pickupPincode,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final ok = await runSellerAction(
      context,
      () async {
        final updated = OwnerSettings.fromJson(await widget.repository.updateSettings({
          'business': {
            'legal_name': _legalName.text.trim(),
            'display_name': _displayName.text.trim(),
            'address': _address.text.trim(),
            'phone': _phone.text.trim(),
            'email': _email.text.trim(),
            'gstin': _gstin.text.trim().toUpperCase(),
            'support_phone': _supportPhone.text.trim(),
            'support_email': _supportEmail.text.trim(),
            'timezone': _timezone.text.trim(),
            'invoice_terms': _invoiceTerms.text.trim(),
            'pickup_town_id': _pickupTownId ?? '',
            'pickup_pincode': _pickupPincode.text.trim(),
          },
        }));
        widget.onSaved(updated);
        return null;
      },
      success: 'Business identity saved. New invoices use these details.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: sellerPagePadding,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InlineNotice(
              message: 'These details appear on customer documents and invoices. Changes apply to new documents only; historical invoices remain immutable.',
              icon: Icons.receipt_long_outlined,
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Legal identity',
              child: Column(
                children: [
                  TextFormField(
                    controller: _legalName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Registered legal name', hintText: 'As printed on your GST registration'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter the registered legal name.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _displayName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Store display name'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter the store display name.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _gstin,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                    decoration: const InputDecoration(labelText: 'GSTIN', hintText: 'Optional for non-GST businesses'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Registered address'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Contact',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Business phone'),
                          validator: (value) => (value == null || value.trim().isEmpty || isValidPhone(value)) ? null : 'Enter a valid phone number.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Business email'),
                          validator: _emailValidator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _supportPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Customer support phone'),
                          validator: (value) => (value == null || value.trim().isEmpty || isValidPhone(value)) ? null : 'Enter a valid phone number.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _supportEmail,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Customer support email'),
                          validator: _emailValidator,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Pickup location & documents',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _pickupTownId,
                    decoration: const InputDecoration(labelText: 'Pickup town', helperText: 'Used for pickup manifests and courier assignment distance.'),
                    items: [
                      for (final town in widget.data.towns) DropdownMenuItem(value: town.id, child: Text('${town.name} — ${town.district}')),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _pickupTownId = value),
                  ),
                  if (widget.data.towns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Add a town under Team & partners before choosing a pickup location.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: IndiBizzColors.warning)),
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pickupPincode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Pickup PIN code'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      return RegExp(r'^[1-9][0-9]{5}$').hasMatch(text) ? null : 'Enter a valid 6-digit PIN code.';
                    },
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _timezone,
                    decoration: const InputDecoration(labelText: 'Business timezone', hintText: 'Asia/Kolkata'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter a timezone.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _invoiceTerms,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Invoice terms', hintText: 'Printed at the bottom of every invoice'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save business settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : 'Enter a valid email address.';
  }
}

// ---------------------------------------------------------------------------
// Commerce and policies
// ---------------------------------------------------------------------------
class _CommercePolicyForm extends StatefulWidget {
  const _CommercePolicyForm({super.key, required this.repository, required this.data, required this.onSaved});
  final OwnerRepository repository;
  final _SettingsData data;
  final ValueChanged<OwnerSettings> onSaved;

  @override
  State<_CommercePolicyForm> createState() => _CommercePolicyFormState();
}

class _CommercePolicyFormState extends State<_CommercePolicyForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _taxEnabled = _bool(widget.data.settings.commerce, 'tax_enabled');
  late final _taxRate = TextEditingController(text: (_int(widget.data.settings.commerce, 'default_tax_rate_bps') / 100).toString());
  late final _shippingFee = TextEditingController(text: (_int(widget.data.settings.commerce, 'shipping_fee_paise') / 100).toStringAsFixed(2));
  late final _freeShipping = TextEditingController(text: (_int(widget.data.settings.commerce, 'free_shipping_threshold_paise') / 100).toStringAsFixed(2));
  late bool _cancellationAllowed = _bool(widget.data.settings.policies, 'cancellation_allowed_before_pickup', true);
  late final _returnWindow = TextEditingController(text: '${_int(widget.data.settings.policies, 'return_window_days', 7)}');
  bool _saving = false;

  @override
  void dispose() {
    _taxRate.dispose();
    _shippingFee.dispose();
    _freeShipping.dispose();
    _returnWindow.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final ratePercent = double.parse(_taxRate.text.trim());
    final ok = await runSellerAction(
      context,
      () async {
        final updated = OwnerSettings.fromJson(await widget.repository.updateSettings({
          'commerce': {
            'tax_enabled': _taxEnabled,
            'default_tax_rate_bps': (ratePercent * 100).round(),
            'shipping_fee_paise': parseRupeesToPaise(_shippingFee.text) ?? 0,
            'free_shipping_threshold_paise': parseRupeesToPaise(_freeShipping.text) ?? 0,
          },
          'policies': {
            'cancellation_allowed_before_pickup': _cancellationAllowed,
            'return_window_days': int.parse(_returnWindow.text.trim()),
          },
        }));
        widget.onSaved(updated);
        return null;
      },
      success: 'Commerce and policy settings saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: sellerPagePadding,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DetailSection(
              title: 'Pricing and tax',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _taxEnabled,
                    onChanged: _saving ? null : (value) => setState(() => _taxEnabled = value),
                    title: const Text('Charge GST on orders'),
                    subtitle: const Text('Product-level tax rates override this default. Tax is shown separately on the invoice.'),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _taxRate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    enabled: _taxEnabled,
                    decoration: const InputDecoration(labelText: 'Default GST rate (%)', hintText: '0–50'),
                    validator: (value) {
                      if (!_taxEnabled) return null;
                      final rate = double.tryParse(value?.trim() ?? '');
                      if (rate == null || rate < 0 || rate > 50) return 'Enter a rate between 0 and 50.';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Shipping',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _shippingFee,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Shipping fee (₹)', hintText: '0'),
                          validator: _moneyValidator,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _freeShipping,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Free shipping above (₹)', hintText: '0 = disabled'),
                          validator: _moneyValidator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Free shipping threshold of ₹0 disables free shipping. COD is the only payment method in this release.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Customer policies',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _cancellationAllowed,
                    onChanged: _saving ? null : (value) => setState(() => _cancellationAllowed = value),
                    title: const Text('Allow cancellation before pickup'),
                    subtitle: const Text('Once a pickup is verified, customers must use the return process instead.'),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _returnWindow,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Return window (days after delivery)', hintText: '0–30'),
                    validator: (value) {
                      final days = int.tryParse(value?.trim() ?? '');
                      if (days == null || days < 0 || days > 30) return 'Enter 0–30 days.';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save commerce settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _moneyValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return parseRupeesToPaise(text) == null ? 'Enter a valid amount.' : null;
  }
}

// ---------------------------------------------------------------------------
// Logistics and assignment policy
// ---------------------------------------------------------------------------
class _LogisticsForm extends StatefulWidget {
  const _LogisticsForm({super.key, required this.repository, required this.data, required this.onSaved});
  final OwnerRepository repository;
  final _SettingsData data;
  final ValueChanged<OwnerSettings> onSaved;

  @override
  State<_LogisticsForm> createState() => _LogisticsFormState();
}

class _LogisticsFormState extends State<_LogisticsForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _autoCreate = _bool(widget.data.settings.logistics, 'auto_create_delivery_assignment', true);
  late bool _requirePhoto = _bool(widget.data.settings.logistics, 'require_photo');
  late final _maxAttempts = TextEditingController(text: '${_int(widget.data.settings.logistics, 'max_delivery_attempts', 3)}');
  bool _saving = false;

  @override
  void dispose() {
    _maxAttempts.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final ok = await runSellerAction(
      context,
      () async {
        final updated = OwnerSettings.fromJson(await widget.repository.updateSettings({
          'logistics': {
            'auto_create_delivery_assignment': _autoCreate,
            'require_photo': _requirePhoto,
            'max_delivery_attempts': int.parse(_maxAttempts.text.trim()),
          },
        }));
        widget.onSaved(updated);
        return null;
      },
      success: 'Delivery proof settings saved.',
    );
    if (mounted) setState(() => _saving = false);
  }

  Map<String, dynamic>? _policyFor(String? townId) {
    for (final policy in widget.data.settings.assignmentPolicies) {
      final policyTown = policy['town_id']?.toString();
      if (townId == null ? policyTown == null || policyTown.isEmpty : policyTown == townId) return policy;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: sellerPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Form(
            key: _formKey,
            child: DetailSection(
              title: 'Delivery proof',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _autoCreate,
                    onChanged: _saving ? null : (value) => setState(() => _autoCreate = value),
                    title: const Text('Create delivery work after verified pickup'),
                    subtitle: const Text('When disabled, the owner must assign delivery manually from Logistics.'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _requirePhoto,
                    onChanged: _saving ? null : (value) => setState(() => _requirePhoto = value),
                    title: const Text('Require a delivery photo'),
                    subtitle: const Text('Delivery staff must upload door/parcel evidence before completing delivery.'),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _maxAttempts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Maximum delivery attempts', hintText: '1–10'),
                    validator: (value) {
                      final count = int.tryParse(value?.trim() ?? '');
                      if (count == null || count < 1 || count > 10) return 'Enter 1–10 attempts.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(_saving ? 'Saving…' : 'Save delivery settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AssignmentPolicyForm(repository: widget.repository, data: widget.data, onSaved: widget.onSaved, policyFor: _policyFor),
        ],
      ),
    );
  }
}

class _AssignmentPolicyForm extends StatefulWidget {
  const _AssignmentPolicyForm({
    required this.repository,
    required this.data,
    required this.onSaved,
    required this.policyFor,
  });
  final OwnerRepository repository;
  final _SettingsData data;
  final ValueChanged<OwnerSettings> onSaved;
  final Map<String, dynamic>? Function(String? townId) policyFor;

  @override
  State<_AssignmentPolicyForm> createState() => _AssignmentPolicyFormState();
}

class _AssignmentPolicyFormState extends State<_AssignmentPolicyForm> {
  String? _townId;
  late Map<String, dynamic> _policy = widget.policyFor(null) ?? const {};
  late bool _autoAssign = _bool(_policy, 'auto_assign_enabled', true);
  late bool _manualOnly = _bool(_policy, 'manual_only');
  late bool _allowOverride = _bool(_policy, 'allow_manual_override', true);
  late bool _autoCreateDelivery = _bool(_policy, 'auto_create_delivery_assignment', true);
  late bool _preferOwnTeam = _bool(_policy, 'prefer_own_team', true);
  late bool _retry = _bool(_policy, 'retry_on_rejection', true);
  late final _timeout = TextEditingController(text: '${_int(_policy, 'offer_timeout_seconds', 300)}');
  late final _maxActive = TextEditingController(text: '${_int(_policy, 'max_active_tasks_per_staff', 10)}');
  late final _weightWorkload = TextEditingController(text: '${_double(_policy, 'weight_workload', 10)}');
  late final _weightDistance = TextEditingController(text: '${_double(_policy, 'weight_distance', 1)}');
  late final _candidateLimit = TextEditingController(text: '${_int(_policy, 'candidate_limit', 20)}');
  bool _saving = false;

  @override
  void dispose() {
    _timeout.dispose();
    _maxActive.dispose();
    _weightWorkload.dispose();
    _weightDistance.dispose();
    _candidateLimit.dispose();
    super.dispose();
  }

  void _selectTown(String? townId) {
    final policy = widget.policyFor(townId) ?? const <String, dynamic>{};
    setState(() {
      _townId = townId;
      _policy = policy;
      _autoAssign = _bool(policy, 'auto_assign_enabled', true);
      _manualOnly = _bool(policy, 'manual_only');
      _allowOverride = _bool(policy, 'allow_manual_override', true);
      _autoCreateDelivery = _bool(policy, 'auto_create_delivery_assignment', true);
      _preferOwnTeam = _bool(policy, 'prefer_own_team', true);
      _retry = _bool(policy, 'retry_on_rejection', true);
      _timeout.text = '${_int(policy, 'offer_timeout_seconds', 300)}';
      _maxActive.text = '${_int(policy, 'max_active_tasks_per_staff', 10)}';
      _weightWorkload.text = '${_double(policy, 'weight_workload', 10)}';
      _weightDistance.text = '${_double(policy, 'weight_distance', 1)}';
      _candidateLimit.text = '${_int(policy, 'candidate_limit', 20)}';
    });
  }

  Future<void> _save() async {
    final timeout = int.tryParse(_timeout.text.trim());
    final maxActive = int.tryParse(_maxActive.text.trim());
    final candidateLimit = int.tryParse(_candidateLimit.text.trim());
    final workload = double.tryParse(_weightWorkload.text.trim());
    final distance = double.tryParse(_weightDistance.text.trim());
    if (timeout == null || timeout < 30 || timeout > 86400) {
      showToast(context, 'Offer timeout must be between 30 and 86400 seconds.', error: true);
      return;
    }
    if (maxActive == null || maxActive < 1 || maxActive > 200) {
      showToast(context, 'Maximum active tasks must be between 1 and 200.', error: true);
      return;
    }
    if (candidateLimit == null || candidateLimit < 1 || candidateLimit > 200) {
      showToast(context, 'Candidate limit must be between 1 and 200.', error: true);
      return;
    }
    if (workload == null || distance == null || workload < 0 || distance < 0) {
      showToast(context, 'Scoring weights must be non-negative numbers.', error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await runSellerAction(
      context,
      () async {
        await widget.repository.updateAssignmentPolicy(_townId, {
          'auto_assign_enabled': _autoAssign,
          'manual_only': _manualOnly,
          'allow_manual_override': _allowOverride,
          'auto_create_delivery_assignment': _autoCreateDelivery,
          'offer_timeout_seconds': timeout,
          'max_active_tasks_per_staff': maxActive,
          'prefer_own_team': _preferOwnTeam,
          'weight_workload': workload,
          'weight_distance': distance,
          'candidate_limit': candidateLimit,
          'retry_on_rejection': _retry,
        });
        widget.onSaved(await widget.repository.getSettings());
      },
      success: 'Assignment policy saved for ${_townId == null ? 'all towns' : 'the selected town'}.',
    );
    if (mounted) setState(() => _saving = false);
    if (!ok) return;
  }

  @override
  Widget build(BuildContext context) {
    final overridden = _townId != null && _policy.isNotEmpty;
    return DetailSection(
      title: 'Pickup & delivery assignment',
      trailing: overridden ? const Tag(text: 'Town override', icon: Icons.tune_rounded) : const Tag(text: 'Global default', icon: Icons.public_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Work is scored automatically by workload, distance and team preference. The owner can always override or reassign manually.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _townId,
            decoration: const InputDecoration(labelText: 'Policy scope'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All towns (global default)')),
              for (final town in widget.data.towns) DropdownMenuItem<String?>(value: town.id, child: Text('${town.name} override')),
            ],
            onChanged: _saving ? null : _selectTown,
          ),
          if (overridden) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final confirmed = await confirmAction(
                          context,
                          title: 'Remove town override?',
                          message: 'The town will use the global assignment policy again.',
                          confirmLabel: 'Remove override',
                          destructive: true,
                        );
                        if (!confirmed || !mounted) return;
                        final ok = await runSellerAction(
                          context,
                          () async {
                            await widget.repository.updateAssignmentPolicy(_townId, {
                              'auto_assign_enabled': true,
                              'manual_only': false,
                              'allow_manual_override': true,
                              'auto_create_delivery_assignment': true,
                              'offer_timeout_seconds': 300,
                              'max_active_tasks_per_staff': 10,
                              'prefer_own_team': true,
                              'weight_workload': 10,
                              'weight_distance': 1,
                              'candidate_limit': 20,
                              'retry_on_rejection': true,
                            });
                            return null;
                          },
                          success: 'Town policy reset to the defaults.',
                        );
                        if (ok && mounted) _selectTown(null);
                      },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Reset this town to defaults'),
              ),
            ),
          ],
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoAssign,
            onChanged: _saving ? null : (value) => setState(() => _autoAssign = value),
            title: const Text('Automatic assignment'),
            subtitle: const Text('Offer new pickups and deliveries to the best available person.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _manualOnly,
            onChanged: _saving ? null : (value) => setState(() => _manualOnly = value),
            title: const Text('Manual assignment only'),
            subtitle: const Text('Disables offers; the owner assigns every task from Logistics.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allowOverride,
            onChanged: _saving ? null : (value) => setState(() => _allowOverride = value),
            title: const Text('Allow manual override'),
            subtitle: const Text('The owner may reassign tasks before they are accepted or started.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoCreateDelivery,
            onChanged: _saving ? null : (value) => setState(() => _autoCreateDelivery = value),
            title: const Text('Create delivery work after verified pickup'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _preferOwnTeam,
            onChanged: _saving ? null : (value) => setState(() => _preferOwnTeam = value),
            title: const Text('Prefer own delivery staff'),
            subtitle: const Text('Own staff win ties against partners, subject to capacity.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _retry,
            onChanged: _saving ? null : (value) => setState(() => _retry = value),
            title: const Text('Retry after a declined offer'),
            subtitle: const Text('Offer the task to the next best candidate instead of waiting for manual assignment.'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _NumberField(controller: _timeout, label: 'Offer timeout (seconds)', decimal: false)),
              const SizedBox(width: 10),
              Expanded(child: _NumberField(controller: _maxActive, label: 'Max active tasks per person', decimal: false)),
              const SizedBox(width: 10),
              Expanded(child: _NumberField(controller: _candidateLimit, label: 'Candidate limit', decimal: false)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _NumberField(controller: _weightWorkload, label: 'Workload weight', decimal: true)),
              const SizedBox(width: 10),
              Expanded(child: _NumberField(controller: _weightDistance, label: 'Distance weight', decimal: true)),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save assignment policy'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label, required this.decimal});
  final TextEditingController controller;
  final String label;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label),
    );
  }
}

// ---------------------------------------------------------------------------
// Audit trail
// ---------------------------------------------------------------------------
class _AuditTab extends StatefulWidget {
  const _AuditTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  final _search = TextEditingController();
  String? _entity;
  int _revision = 0;

  static const _entities = <String?>[null, 'order', 'shipment', 'pickup', 'product', 'stock_movement', 'cod_settlement', 'return', 'staff', 'staff_invite', 'delivery_partner', 'town', 'serviceable_pincode', 'app_settings', 'assignment_policy'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            children: [
              SearchField(
                controller: _search,
                hint: 'Search action, entity or actor…',
                onSubmitted: (_) => _reload(),
              ),
              const SizedBox(height: 8),
              FilterChipRow(
                values: _entities,
                selected: _entity,
                labelFor: (value) => value == null ? 'All activity' : titleCase(value.replaceAll('_', ' ')),
                onSelected: (value) {
                  setState(() {
                    _entity = value;
                    _revision++;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: OwnerAsyncPage<List<AuditLog>>(
            key: ValueKey('audit-$_revision'),
            scrollable: true,
            load: () => widget.repository.listAuditLogs(limit: 150, entityType: _entity, search: _search.text.trim().isEmpty ? null : _search.text.trim()),
            loadingLabel: 'Loading audit trail…',
            emptyTitle: 'No audit entries',
            emptyMessage: 'Every business action is recorded here with the actor, source and immutable before/after data.',
            emptyIcon: Icons.history_rounded,
            isEmpty: (data) => data.isEmpty,
            builder: (context, logs, refresh) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${logs.length} recorded ${logs.length == 1 ? 'action' : 'actions'}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Audit entries are append-only. They cannot be edited or deleted from any client.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final log in logs) ...[
                  _AuditCard(log: log),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.log});
  final AuditLog log;

  void _showDetails(BuildContext context) {
    final before = const JsonEncoder.withIndent('  ').convert(log.beforeData.isEmpty ? null : log.beforeData);
    final after = const JsonEncoder.withIndent('  ').convert(log.afterData.isEmpty ? null : log.afterData);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(titleCase(log.action.replaceAll('_', ' ')), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${log.entityType} • ${formatDateTime(log.createdAt, includeYear: true)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            DetailSection(
              title: 'Context',
              child: Column(
                children: [
                  KeyValueRow(label: 'Actor', value: log.actorName ?? 'System'),
                  KeyValueRow(label: 'Role', value: log.actorRole ?? '—'),
                  KeyValueRow(label: 'Source', value: log.source ?? '—'),
                  KeyValueRow(label: 'Entity ID', value: log.entityId ?? '—'),
                  KeyValueRow(label: 'Audit ID', value: log.id),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Before',
              child: _JsonBlock(text: before),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'After',
              child: _JsonBlock(text: after),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(13),
      onTap: () => _showDetails(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.canvas,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.history_rounded, size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(titleCase(log.action.replaceAll('_', ' ')), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5)),
                    Tag(text: log.entityType),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${log.actorName ?? 'System'}${log.actorRole == null ? '' : ' • ${titleCase(log.actorRole!.replaceAll('_', ' '))}'} • ${formatDateTime(log.createdAt, includeYear: true)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                if (log.afterData.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    log.afterData.entries.take(3).map((entry) => '${entry.key}: ${entry.value}').join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.45),
      ),
    );
  }
}
