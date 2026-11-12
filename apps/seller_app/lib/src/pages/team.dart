import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key, required this.repository});
  final OwnerRepository repository;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  int _tab = 0;

  static const _tabs = ['staff', 'partners', 'areas'];
  static const _labels = ['Staff', 'Partners', 'Towns & PIN codes'];

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
              _StaffTab(repository: widget.repository),
              _PartnersTab(repository: widget.repository),
              _AreasTab(repository: widget.repository),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------
class _StaffData {
  const _StaffData(this.personnel, this.invites, this.partners);
  final List<Personnel> personnel;
  final List<StaffInvite> invites;
  final List<Partner> partners;
}

class _StaffTab extends StatefulWidget {
  const _StaffTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  int _revision = 0;

  Future<_StaffData> _load() async {
    final results = await Future.wait([
      widget.repository.listDeliveryPersonnel(),
      widget.repository.listStaffInvites(),
      widget.repository.listPartners(),
    ]);
    return _StaffData(
      results[0] as List<Personnel>,
      results[1] as List<StaffInvite>,
      results[2] as List<Partner>,
    );
  }

  Future<void> _invite(List<Partner> partners) async {
    final invite = await showDialog<StaffInvite>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _InviteDialog(repository: widget.repository, partners: partners),
    );
    if (invite == null || !mounted) return;
    setState(() => _revision++);
    final code = invite.activationCode;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invitation created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share this single-use activation code privately with ${invite.displayName}.'),
            const SizedBox(height: 12),
            SelectableText(
              code ?? 'Code not returned',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3),
            ),
            const SizedBox(height: 10),
            Text(
              'For ${formatPhone(invite.phone)} • expires ${formatDateTime(invite.expiresAt, includeYear: true)}. '
              'The code is hashed on the server and cannot be shown again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (code != null)
            TextButton.icon(
              onPressed: () => copyText(context, code, label: 'Activation code'),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy code'),
            ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _edit(Personnel staff) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _StaffEditDialog(repository: widget.repository, staff: staff),
    );
    if (result != null && mounted) setState(() => _revision++);
  }

  Future<void> _coverage(Personnel staff) async {
    final towns = await widget.repository.listTowns();
    if (!mounted) return;
    final areas = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => _CoverageDialog(
        towns: towns,
        title: 'Coverage for ${staff.displayName}',
        initialAreas: const [],
      ),
    );
    if (areas == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.setStaffCoverage(staff.staffUserId, areas),
      success: 'Coverage updated for ${staff.displayName}.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _toggleAvailability(Personnel staff, bool value) async {
    final ok = await runSellerAction(
      context,
      () => widget.repository.setStaffAvailability(staff.staffUserId, value),
      success: value ? '${staff.displayName} is available for new work.' : '${staff.displayName} will receive no new work.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _suspend(Personnel staff) async {
    final reason = await askReason(
      context,
      title: 'Suspend ${staff.displayName}',
      hint: 'Reason recorded in the audit trail',
      confirmLabel: 'Suspend',
    );
    if (reason == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.suspendDeliveryPerson(staff.staffUserId, reason),
      success: '${staff.displayName} suspended.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _reactivate(Personnel staff) async {
    final ok = await runSellerAction(
      context,
      () => widget.repository.reactivateDeliveryPerson(staff.staffUserId),
      success: '${staff.displayName} reactivated.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _revoke(StaffInvite invite) async {
    final confirmed = await confirmAction(
      context,
      title: 'Revoke invitation?',
      message: '${invite.displayName} will not be able to use this activation code.',
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.revokeStaffInvite(invite.id),
      success: 'Invitation revoked.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAsyncPage<_StaffData>(
      key: ValueKey('staff-$_revision'),
      scrollable: true,
      load: _load,
      loadingLabel: 'Loading team…',
      emptyTitle: 'No delivery people yet',
      emptyMessage: 'Invite your own delivery staff or onboard a delivery partner. Staff accept work only after redeeming a single-use code.',
      emptyIcon: Icons.groups_outlined,
      isEmpty: (data) => data.personnel.isEmpty && data.invites.isEmpty,
      builder: (context, data, refresh) {
        final activeInvites = data.invites.where((invite) => invite.revokedAt == null).toList(growable: false);
        final active = data.personnel.where((person) => person.status == 'ACTIVE').toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${active.length} active delivery ${active.length == 1 ? 'person' : 'people'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _invite(data.partners),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Invite staff'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.personnel.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InlineNotice(
                  message: 'No staff have activated an invitation yet. Create one above and share the code privately.',
                  icon: Icons.info_outline_rounded,
                ),
              ),
            for (final person in data.personnel) ...[
              _StaffCard(
                person: person,
                onAvailabilityChanged: person.status == 'ACTIVE' ? (value) => _toggleAvailability(person, value) : null,
                onEdit: () => _edit(person),
                onCoverage: () => _coverage(person),
                onSuspend: person.status == 'ACTIVE' ? () => _suspend(person) : null,
                onReactivate: person.status != 'ACTIVE' ? () => _reactivate(person) : null,
              ),
              const SizedBox(height: 9),
            ],
            if (activeInvites.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Pending invitations', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final invite in activeInvites) ...[
                _InviteCard(invite: invite, onRevoke: () => _revoke(invite)),
                const SizedBox(height: 9),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.person,
    required this.onAvailabilityChanged,
    required this.onEdit,
    required this.onCoverage,
    required this.onSuspend,
    required this.onReactivate,
  });

  final Personnel person;
  final ValueChanged<bool>? onAvailabilityChanged;
  final VoidCallback onEdit;
  final VoidCallback onCoverage;
  final VoidCallback? onSuspend;
  final VoidCallback? onReactivate;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final partner = person.staffType != 'OWN';
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: person.displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(person.displayName, style: Theme.of(context).textTheme.titleSmall),
                        Tag(text: partner ? (person.partnerName ?? 'Partner') : 'Own team', icon: partner ? Icons.handshake_outlined : Icons.storefront_outlined),
                        StatusBadge(status: person.status),
                        if (!person.isAvailable && person.status == 'ACTIVE') const Tag(text: 'Unavailable', icon: Icons.pause_circle_outline),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (person.employeeCode != null && person.employeeCode!.isNotEmpty) person.employeeCode!,
                        if (person.phone != null) formatPhone(person.phone),
                        if (person.coverageLabel.isNotEmpty) person.coverageLabel,
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: person.isAvailable,
                onChanged: onAvailabilityChanged,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Tag(text: 'Capacity ${person.capacityPerDay}/day', icon: Icons.assignment_outlined),
              const SizedBox(width: 6),
              Tag(text: '${person.activeTasks} active', icon: Icons.pending_actions_outlined),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.border),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Edit')),
              TextButton.icon(onPressed: onCoverage, icon: const Icon(Icons.pin_drop_outlined, size: 15), label: const Text('Coverage')),
              if (onSuspend != null)
                TextButton.icon(
                  onPressed: onSuspend,
                  icon: const Icon(Icons.block_outlined, size: 15),
                  label: const Text('Suspend'),
                  style: TextButton.styleFrom(foregroundColor: IndiBizzColors.danger),
                ),
              if (onReactivate != null)
                TextButton.icon(onPressed: onReactivate, icon: const Icon(Icons.play_circle_outline, size: 15), label: const Text('Reactivate')),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite, required this.onRevoke});
  final StaffInvite invite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final expired = !invite.expiresAt.isAfter(DateTime.now());
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          UserAvatar(name: invite.displayName, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(invite.displayName, style: Theme.of(context).textTheme.titleSmall),
                    Tag(text: invite.role == 'PARTNER_ADMIN' ? 'Partner admin' : invite.role == 'PARTNER_DELIVERY_STAFF' ? 'Partner staff' : 'Own staff'),
                    if (invite.usedAt != null)
                      const Tag(text: 'Used')
                    else if (invite.revokedAt != null)
                      const Tag(text: 'Revoked')
                    else if (expired)
                      const Tag(text: 'Expired')
                    else
                      const Tag(text: 'Awaiting activation'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatPhone(invite.phone)}${invite.partnerName == null ? '' : ' • ${invite.partnerName}'} • expires ${formatDateTime(invite.expiresAt, includeYear: true)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (invite.usedAt == null && invite.revokedAt == null && !expired)
            IconButton(
              tooltip: 'Revoke invitation',
              onPressed: onRevoke,
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
            ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.repository, required this.partners});
  final OwnerRepository repository;
  final List<Partner> partners;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'OWN_DELIVERY_STAFF';
  String? _partnerId;
  bool _canManage = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_role != 'OWN_DELIVERY_STAFF' && _partnerId == null) {
      setState(() => _error = 'Select the delivery partner this person belongs to.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final invite = await widget.repository.createStaffInvite(
        phone: normalizePhone(_phone.text),
        role: _role,
        displayName: _name.text.trim(),
        partnerId: _role == 'OWN_DELIVERY_STAFF' ? null : _partnerId,
        canManagePartnerStaff: _role == 'PARTNER_ADMIN' && _canManage,
      );
      if (!mounted) return;
      Navigator.of(context).pop(invite);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerRoles = _role != 'OWN_DELIVERY_STAFF';
    return AlertDialog(
      title: const Text('Invite delivery staff'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InlineNotice(
                  message: 'The invitee signs in with their own phone OTP, then redeems this single-use code once. You can revoke unused invitations at any time.',
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) => (value == null || value.trim().length < 2) ? 'Enter the staff member’s name.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number', prefixText: '+91 ', helperText: 'They must sign in with this exact number.'),
                  validator: (value) => isValidPhone(value ?? '') ? null : 'Enter a valid phone number.',
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'OWN_DELIVERY_STAFF', child: Text('Own delivery staff')),
                    DropdownMenuItem(value: 'PARTNER_ADMIN', child: Text('Partner administrator')),
                    DropdownMenuItem(value: 'PARTNER_DELIVERY_STAFF', child: Text('Partner delivery staff')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                            _role = value ?? 'OWN_DELIVERY_STAFF';
                            if (_role == 'OWN_DELIVERY_STAFF') _partnerId = null;
                          }),
                ),
                if (partnerRoles) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _partnerId,
                    decoration: const InputDecoration(labelText: 'Delivery partner'),
                    items: [
                      for (final partner in widget.partners)
                        DropdownMenuItem(value: partner.id, child: Text('${partner.name} (${partner.code})')),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _partnerId = value),
                  ),
                  if (widget.partners.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Create a delivery partner before inviting partner staff.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: IndiBizzColors.danger)),
                    ),
                  if (_role == 'PARTNER_ADMIN')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _canManage,
                      onChanged: _saving ? null : (value) => setState(() => _canManage = value),
                      title: const Text('Can invite and manage partner staff'),
                      subtitle: const Text('The partner administrator will be able to onboard their own delivery staff.'),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: IndiBizzColors.danger, fontSize: 12.5, height: 1.4)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create invitation'),
        ),
      ],
    );
  }
}

class _StaffEditDialog extends StatefulWidget {
  const _StaffEditDialog({required this.repository, required this.staff});
  final OwnerRepository repository;
  final Personnel staff;

  @override
  State<_StaffEditDialog> createState() => _StaffEditDialogState();
}

class _StaffEditDialogState extends State<_StaffEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.staff.displayName);
  late final _code = TextEditingController(text: widget.staff.employeeCode ?? '');
  late final _capacity = TextEditingController(text: widget.staff.capacityPerDay == 0 ? '25' : '${widget.staff.capacityPerDay}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.updateStaffProfile(
        staffUserId: widget.staff.staffUserId,
        displayName: _name.text.trim(),
        capacityPerDay: int.parse(_capacity.text.trim()),
        employeeCode: _code.text.trim().isEmpty ? null : _code.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit staff profile'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a display name.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Employee code', hintText: 'Optional internal code'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Daily task capacity', helperText: 'Maximum active pickups and deliveries assigned per day.'),
                validator: (value) {
                  final capacity = int.tryParse(value?.trim() ?? '');
                  if (capacity == null || capacity < 1 || capacity > 200) return 'Enter a capacity between 1 and 200.';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: IndiBizzColors.danger, fontSize: 12.5))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save profile')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Partners
// ---------------------------------------------------------------------------
class _PartnersTab extends StatefulWidget {
  const _PartnersTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab> {
  int _revision = 0;

  Future<void> _save([Partner? partner]) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (context) => _PartnerDialog(repository: widget.repository, partner: partner),
    );
    if (result != null && mounted) setState(() => _revision++);
  }

  Future<void> _status(Partner partner, String status) async {
    String? reason;
    if (status == 'SUSPENDED') {
      reason = await askReason(
        context,
        title: 'Suspend ${partner.name}',
        hint: 'Reason recorded in the audit trail',
        confirmLabel: 'Suspend partner',
      );
      if (reason == null || !mounted) return;
    }
    final ok = await runSellerAction(
      context,
      () => widget.repository.setPartnerStatus(partner.id, status, reason: reason),
      success: status == 'ACTIVE' ? '${partner.name} activated.' : status == 'SUSPENDED' ? '${partner.name} suspended.' : 'Partner status updated.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _coverage(Partner partner) async {
    final towns = await widget.repository.listTowns();
    if (!mounted) return;
    final areas = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => _CoverageDialog(
        towns: towns,
        title: 'Coverage for ${partner.name}',
        initialAreas: [
          for (final area in partner.coverage) {'town_id': area.townId, if (area.pincode != null) 'pincode': area.pincode},
        ],
      ),
    );
    if (areas == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.setPartnerCoverage(partner.id, areas),
      success: 'Coverage updated for ${partner.name}.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAsyncPage<List<Partner>>(
      key: ValueKey('partners-$_revision'),
      scrollable: true,
      load: widget.repository.listPartners,
      loadingLabel: 'Loading partners…',
      emptyTitle: 'No delivery partners',
      emptyMessage: 'Add a partner, define their coverage and invite their administrator. Partners only receive work in the towns and PIN codes you enable.',
      emptyIcon: Icons.handshake_outlined,
      isEmpty: (data) => data.isEmpty,
      builder: (context, partners, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${partners.length} delivery ${partners.length == 1 ? 'partner' : 'partners'}', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.icon(onPressed: () => _save(), icon: const Icon(Icons.add_business_outlined, size: 18), label: const Text('Add partner')),
            ],
          ),
          const SizedBox(height: 12),
          for (final partner in partners) ...[
            _PartnerCard(
              partner: partner,
              onEdit: () => _save(partner),
              onCoverage: () => _coverage(partner),
              onActivate: partner.status == 'ACTIVE' ? null : () => _status(partner, 'ACTIVE'),
              onSuspend: partner.status == 'SUSPENDED' ? null : () => _status(partner, 'SUSPENDED'),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.partner,
    required this.onEdit,
    required this.onCoverage,
    required this.onActivate,
    required this.onSuspend,
  });
  final Partner partner;
  final VoidCallback onEdit;
  final VoidCallback onCoverage;
  final VoidCallback? onActivate;
  final VoidCallback? onSuspend;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: partner.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(partner.name, style: Theme.of(context).textTheme.titleSmall),
                        Tag(text: partner.code),
                        StatusBadge(status: partner.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (partner.contactName.isNotEmpty) partner.contactName,
                        if (partner.phone != null) formatPhone(partner.phone),
                        if (partner.email != null && partner.email!.isNotEmpty) partner.email!,
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tag(text: '${partner.activeStaffCount}/${partner.staffCount} staff active', icon: Icons.groups_outlined),
              Tag(text: 'COD limit ${formatMoney(partner.codCreditLimitPaise)}', icon: Icons.account_balance_wallet_outlined),
              Tag(text: 'Settlement ${partner.settlementCycleDays}d', icon: Icons.event_repeat_outlined),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            partner.coverage.isEmpty ? 'No coverage yet — this partner cannot receive work.' : 'Covers ${partner.coverage.map((area) => area.pincode == null ? area.townName : '${area.townName} ${area.pincode}').join(', ')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: partner.coverage.isEmpty ? IndiBizzColors.warning : null,
                ),
          ),
          if (partner.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(partner.notes, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.border),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Edit')),
              TextButton.icon(onPressed: onCoverage, icon: const Icon(Icons.pin_drop_outlined, size: 15), label: const Text('Coverage')),
              if (onActivate != null) TextButton.icon(onPressed: onActivate, icon: const Icon(Icons.check_circle_outline, size: 15), label: const Text('Activate')),
              if (onSuspend != null)
                TextButton.icon(
                  onPressed: onSuspend,
                  icon: const Icon(Icons.block_outlined, size: 15),
                  label: const Text('Suspend'),
                  style: TextButton.styleFrom(foregroundColor: IndiBizzColors.danger),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartnerDialog extends StatefulWidget {
  const _PartnerDialog({required this.repository, this.partner});
  final OwnerRepository repository;
  final Partner? partner;

  @override
  State<_PartnerDialog> createState() => _PartnerDialogState();
}

class _PartnerDialogState extends State<_PartnerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.partner?.name ?? '');
  late final _code = TextEditingController(text: widget.partner?.code ?? '');
  late final _contact = TextEditingController(text: widget.partner?.contactName ?? '');
  late final _phone = TextEditingController(text: widget.partner?.phone ?? '');
  late final _email = TextEditingController(text: widget.partner?.email ?? '');
  late final _credit = TextEditingController(text: widget.partner == null ? '' : (widget.partner!.codCreditLimitPaise / 100).toStringAsFixed(2));
  late final _cycle = TextEditingController(text: '${widget.partner?.settlementCycleDays ?? 1}');
  late final _notes = TextEditingController(text: widget.partner?.notes ?? '');
  late String _status = widget.partner?.status ?? 'PENDING';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _credit.dispose();
    _cycle.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.savePartner(
        id: widget.partner?.id,
        name: _name.text.trim(),
        code: _code.text.trim().toUpperCase(),
        contactName: _contact.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : normalizePhone(_phone.text),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        status: _status,
        codCreditLimitPaise: parseRupeesToPaise(_credit.text) ?? 0,
        settlementCycleDays: int.parse(_cycle.text.trim()),
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.partner == null ? 'Add delivery partner' : 'Edit delivery partner'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Partner name'),
                        validator: (value) => (value == null || value.trim().length < 2) ? 'Enter the partner name.' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Code', hintText: 'PARTNER01'),
                        validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a unique code.' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _contact,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Contact person'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                        validator: (value) => (value == null || value.trim().isEmpty || isValidPhone(value)) ? null : 'Enter a valid phone number.',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : 'Enter a valid email address.';
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _credit,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'COD credit limit (₹)', hintText: '0'),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          return parseRupeesToPaise(text) == null ? 'Enter a valid amount.' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _cycle,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Settlement cycle (days)'),
                        validator: (value) {
                          final days = int.tryParse(value?.trim() ?? '');
                          if (days == null || days < 0 || days > 30) return 'Enter 0–30 days.';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'PENDING', child: Text('Pending — onboarding')),
                    DropdownMenuItem(value: 'ACTIVE', child: Text('Active — can receive work')),
                    DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended — no new work')),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _status = value ?? 'PENDING'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Internal notes'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: IndiBizzColors.danger, fontSize: 12.5))),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : widget.partner == null ? 'Create partner' : 'Save changes')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Towns and PIN codes
// ---------------------------------------------------------------------------
class _AreasTab extends StatefulWidget {
  const _AreasTab({required this.repository});
  final OwnerRepository repository;

  @override
  State<_AreasTab> createState() => _AreasTabState();
}

class _AreasTabState extends State<_AreasTab> {
  int _revision = 0;

  Future<void> _saveTown([AdminTown? town]) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (context) => _TownDialog(repository: widget.repository, town: town),
    );
    if (result != null && mounted) setState(() => _revision++);
  }

  Future<void> _addPincode(AdminTown town) async {
    final pincode = await showDialog<String>(
      context: context,
      builder: (context) => _PincodeDialog(town: town),
    );
    if (pincode == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.addPincode(town.id, pincode),
      success: 'PIN code $pincode added to ${town.name}.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _togglePincode(AdminTown town, PincodeInfo pincode) async {
    final ok = await runSellerAction(
      context,
      () => widget.repository.setPincodeActive(pincode.id, !pincode.isActive),
      success: pincode.isActive ? 'PIN code ${pincode.pincode} disabled.' : 'PIN code ${pincode.pincode} enabled.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAsyncPage<List<AdminTown>>(
      key: ValueKey('areas-$_revision'),
      scrollable: true,
      load: widget.repository.listTowns,
      loadingLabel: 'Loading service areas…',
      emptyTitle: 'No serviceable towns',
      emptyMessage: 'Add the first town, then enable the PIN codes where you can deliver. Customers outside these areas cannot place orders.',
      emptyIcon: Icons.map_outlined,
      isEmpty: (data) => data.isEmpty,
      builder: (context, towns, refresh) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${towns.length} ${towns.length == 1 ? 'town' : 'towns'}', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.icon(onPressed: () => _saveTown(), icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('Add town')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Only enabled PIN codes are serviceable. Changing coverage never rewrites historical orders.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final town in towns) ...[
            _TownCard(
              town: town,
              onEdit: () => _saveTown(town),
              onAddPincode: () => _addPincode(town),
              onTogglePincode: (pincode) => _togglePincode(town, pincode),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _TownCard extends StatelessWidget {
  const _TownCard({required this.town, required this.onEdit, required this.onAddPincode, required this.onTogglePincode});
  final AdminTown town;
  final VoidCallback onEdit;
  final VoidCallback onAddPincode;
  final ValueChanged<PincodeInfo> onTogglePincode;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = town.pincodes.where((pin) => pin.isActive).length;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(town.name, style: Theme.of(context).textTheme.titleSmall),
                        StatusBadge(status: town.isActive ? 'ACTIVE' : 'INACTIVE'),
                        Tag(text: '$enabled/${town.pincodes.length} PIN codes'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${town.district}, ${town.state}${town.latitude != null && town.longitude != null ? ' • ${town.latitude!.toStringAsFixed(4)}, ${town.longitude!.toStringAsFixed(4)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${town.ownStaffCovered} own staff • ${town.partnersCovered} partners cover this town',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Edit town', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 19)),
            ],
          ),
          const SizedBox(height: 8),
          if (town.pincodes.isEmpty)
            Text('No PIN codes yet. Customers cannot check out until at least one PIN code is enabled.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: IndiBizzColors.warning, fontSize: 11.5))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pincode in town.pincodes)
                  InputChip(
                    label: Text(pincode.pincode),
                    selected: pincode.isActive,
                    showCheckmark: false,
                    avatar: Icon(
                      pincode.isActive ? Icons.check_circle_outline : Icons.pause_circle_outline,
                      size: 15,
                      color: pincode.isActive ? IndiBizzColors.success : null,
                    ),
                    onPressed: () => onTogglePincode(pincode),
                    tooltip: pincode.isActive ? 'Enabled — tap to disable' : 'Disabled — tap to enable',
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.border),
          const SizedBox(height: 6),
          TextButton.icon(onPressed: onAddPincode, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add PIN code')),
        ],
      ),
    );
  }
}

class _TownDialog extends StatefulWidget {
  const _TownDialog({required this.repository, this.town});
  final OwnerRepository repository;
  final AdminTown? town;

  @override
  State<_TownDialog> createState() => _TownDialogState();
}

class _TownDialogState extends State<_TownDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.town?.name ?? '');
  late final _district = TextEditingController(text: widget.town?.district ?? '');
  late final _state = TextEditingController(text: widget.town?.state ?? '');
  late final _latitude = TextEditingController(text: widget.town?.latitude?.toString() ?? '');
  late final _longitude = TextEditingController(text: widget.town?.longitude?.toString() ?? '');
  late bool _active = widget.town?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _district.dispose();
    _state.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.saveTown(
        id: widget.town?.id,
        name: _name.text.trim(),
        district: _district.text.trim(),
        state: _state.text.trim(),
        latitude: double.tryParse(_latitude.text.trim()),
        longitude: double.tryParse(_longitude.text.trim()),
        isActive: _active,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.town == null ? 'Add town' : 'Edit ${widget.town!.name}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Town or city'),
                  validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a town name.' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _district,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'District'),
                        validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a district.' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _state,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'State'),
                        validator: (value) => (value == null || value.trim().length < 2) ? 'Enter a state.' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latitude,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Latitude', hintText: 'Optional'),
                        validator: _coordinateValidator,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _longitude,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Longitude', hintText: 'Optional'),
                        validator: _coordinateValidator,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: _saving ? null : (value) => setState(() => _active = value),
                  title: const Text('Town is active'),
                  subtitle: const Text('Inactive towns cannot receive new orders. Existing orders continue normally.'),
                ),
                if (_error != null)
                  Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: IndiBizzColors.danger, fontSize: 12.5))),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : widget.town == null ? 'Create town' : 'Save town')),
      ],
    );
  }

  String? _coordinateValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final coordinate = double.tryParse(text);
    if (coordinate == null || coordinate.isNaN) return 'Enter a valid number.';
    return null;
  }
}

class _PincodeDialog extends StatefulWidget {
  const _PincodeDialog({required this.town});
  final AdminTown town;

  @override
  State<_PincodeDialog> createState() => _PincodeDialogState();
}

class _PincodeDialogState extends State<_PincodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pincode = TextEditingController();

  @override
  void dispose() {
    _pincode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add PIN code to ${widget.town.name}'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _pincode,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: '6-digit PIN code'),
            validator: (value) => RegExp(r'^[1-9][0-9]{5}$').hasMatch(value?.trim() ?? '') ? null : 'Enter a valid 6-digit PIN code.',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) Navigator.of(context).pop(_pincode.text.trim());
          },
          child: const Text('Add PIN code'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared coverage editor
// ---------------------------------------------------------------------------
class _CoverageDialog extends StatefulWidget {
  const _CoverageDialog({required this.towns, required this.title, required this.initialAreas});
  final List<AdminTown> towns;
  final String title;
  final List<Map<String, dynamic>> initialAreas;

  @override
  State<_CoverageDialog> createState() => _CoverageDialogState();
}

class _CoverageDialogState extends State<_CoverageDialog> {
  final Map<String, Set<String>> _selected = {};

  @override
  void initState() {
    super.initState();
    for (final area in widget.initialAreas) {
      final townId = area['town_id']?.toString() ?? '';
      if (townId.isEmpty) continue;
      final pincode = area['pincode']?.toString() ?? '';
      _selected.putIfAbsent(townId, () => <String>{});
      if (pincode.isNotEmpty) _selected[townId]!.add(pincode);
    }
  }

  void _toggleTown(AdminTown town, bool selected) {
    setState(() {
      if (selected) {
        _selected.putIfAbsent(town.id, () => <String>{});
      } else {
        _selected.remove(town.id);
      }
    });
  }

  void _togglePincode(AdminTown town, String pincode) {
    setState(() {
      final pins = _selected.putIfAbsent(town.id, () => <String>{});
      if (!pins.remove(pincode)) pins.add(pincode);
    });
  }

  List<Map<String, dynamic>> _areas() {
    final areas = <Map<String, dynamic>>[];
    for (final entry in _selected.entries) {
      if (entry.value.isEmpty) {
        areas.add({'town_id': entry.key});
      } else {
        for (final pincode in entry.value) {
          areas.add({'town_id': entry.key, 'pincode': pincode});
        }
      }
    }
    return areas;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 460,
        child: widget.towns.isEmpty
            ? const EmptyView(title: 'No towns', message: 'Add a town and PIN codes first.', icon: Icons.map_outlined)
            : ListView(
                children: [
                  Text(
                    'Select a whole town, or choose specific PIN codes inside it. A PIN code selection overrides town-wide coverage.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final town in widget.towns)
                    _CoverageTown(
                      town: town,
                      selectedPins: _selected[town.id],
                      onToggleTown: (selected) => _toggleTown(town, selected),
                      onTogglePincode: (pincode) => _togglePincode(town, pincode),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_areas()),
          child: const Text('Save coverage'),
        ),
      ],
    );
  }
}

class _CoverageTown extends StatelessWidget {
  const _CoverageTown({required this.town, required this.selectedPins, required this.onToggleTown, required this.onTogglePincode});
  final AdminTown town;
  final Set<String>? selectedPins;
  final ValueChanged<bool> onToggleTown;
  final ValueChanged<String> onTogglePincode;

  @override
  Widget build(BuildContext context) {
    final selected = selectedPins != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selected,
          onChanged: (value) => onToggleTown(value ?? false),
          title: Text(town.name),
          subtitle: Text('${town.district}, ${town.state}'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: town.pincodes.isEmpty
                ? Text('No PIN codes configured — coverage applies to the whole town.', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11))
                : Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      InputChip(
                        label: const Text('Entire town'),
                        selected: selectedPins!.isEmpty,
                        showCheckmark: false,
                        onPressed: () {
                          for (final pin in selectedPins!.toList(growable: false)) {
                            onTogglePincode(pin);
                          }
                        },
                      ),
                      for (final pin in town.pincodes.where((pin) => pin.isActive))
                        FilterChip(
                          label: Text(pin.pincode),
                          selected: selectedPins!.contains(pin.pincode),
                          onSelected: (_) => onTogglePincode(pin.pincode),
                        ),
                    ],
                  ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
