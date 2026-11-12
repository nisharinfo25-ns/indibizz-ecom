import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class CodPage extends StatefulWidget {
  const CodPage({super.key, required this.repository});
  final OwnerRepository repository;

  @override
  State<CodPage> createState() => _CodPageState();
}

class _CodPageState extends State<CodPage> {
  int _revision = 0;

  Future<void> _confirm(CodSettlement settlement) async {
    final formKey = GlobalKey<FormState>();
    final counted = TextEditingController();
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify cash handover'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${settlement.staffName} declared ${formatMoney(settlement.handedOverPaise)}.', style: const TextStyle(height: 1.5)),
                const SizedBox(height: 6),
                Text(
                  'Collected ${formatMoney(settlement.collectedPaise)} • Expected ${formatMoney(settlement.expectedPaise)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: counted,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cash counted (₹)',
                    helperText: 'Enter the physical amount you counted. Never trust the declared amount.',
                  ),
                  validator: (value) => parseRupeesToPaise(value ?? '') == null ? 'Enter the amount you counted.' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Verification note', hintText: 'Optional context for the ledger'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(context, true);
            },
            child: const Text('Confirm settlement'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      counted.dispose();
      note.dispose();
      return;
    }
    final countedPaise = parseRupeesToPaise(counted.text)!;
    final noteText = note.text.trim();
    counted.dispose();
    note.dispose();
    if (!mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.confirmCodSettlement(
        settlementId: settlement.id,
        countedPaise: countedPaise,
        note: noteText.isEmpty ? null : noteText,
      ),
      success: 'Settlement verified and posted to the COD ledger.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _dispute(CodSettlement settlement) async {
    final reason = await askReason(context, title: 'Dispute settlement', hint: 'Why is this handover being disputed?', confirmLabel: 'Dispute');
    if (reason == null || !mounted) return;
    final ok = await runSellerAction(context, () => widget.repository.disputeCodSettlement(settlement.id, reason), success: 'Settlement disputed. The delivery person can see the reason.');
    if (ok && mounted) setState(() => _revision++);
  }

  void _showSettlement(CodSettlement settlement) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text(settlement.settlementNumber, style: Theme.of(context).textTheme.titleLarge)),
                StatusBadge(status: settlement.status),
              ],
            ),
            const SizedBox(height: 6),
            Text('${settlement.staffName} • ${settlement.staffType == 'OWN' ? 'Own team' : settlement.partnerName ?? 'Partner'}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            SurfaceCard(
              child: Column(
                children: [
                  KeyValueRow(label: 'Expected COD', value: formatMoney(settlement.expectedPaise)),
                  KeyValueRow(label: 'Collected', value: formatMoney(settlement.collectedPaise)),
                  KeyValueRow(label: 'Declared handover', value: formatMoney(settlement.handedOverPaise)),
                  KeyValueRow(label: 'Counted by owner', value: formatMoney(settlement.countedPaise)),
                  KeyValueRow(label: 'Shortage', value: formatMoney(settlement.shortagePaise), valueColor: settlement.shortagePaise > 0 ? IndiBizzColors.danger : null),
                  KeyValueRow(label: 'Excess', value: formatMoney(settlement.excessPaise)),
                  KeyValueRow(label: 'Declared', value: formatDateTime(settlement.declaredAt, includeYear: true)),
                  if (settlement.verifiedAt != null) KeyValueRow(label: 'Verified', value: formatDateTime(settlement.verifiedAt, includeYear: true)),
                ],
              ),
            ),
            if (settlement.note != null && settlement.note!.isNotEmpty) ...[
              const SizedBox(height: 10),
              InlineNotice(title: 'Owner note', message: settlement.note!, tone: StatusTone.muted),
            ],
            if (settlement.rejectionReason != null && settlement.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 10),
              InlineNotice(title: 'Dispute reason', message: settlement.rejectionReason!, tone: StatusTone.danger),
            ],
            const SizedBox(height: 16),
            Text('Shipments in this handover', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (settlement.items.isEmpty)
              Text('Item lines are included when the settlement is opened in the COD overview.', style: Theme.of(context).textTheme.bodySmall)
            else
              for (final item in settlement.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.shipmentNumber, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5)),
                            Text(item.orderNumber, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(paise: item.collectedPaise, size: 13),
                          Text('Expected ${formatMoney(item.expectedPaise)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OwnerAsyncPage<CodOverview>(
      key: ValueKey('cod-$_revision'),
      load: widget.repository.codOverview,
      loadingLabel: 'Reconciling the COD ledger…',
      emptyTitle: 'No COD activity yet',
      emptyMessage: 'Collected cash, handovers and owner verification will appear here.',
      emptyIcon: Icons.account_balance_wallet_outlined,
      builder: (context, data, refresh) => PageScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final tileWidth = width >= 1040 ? (width - 36) / 4 : width >= 620 ? (width - 12) / 2 : width;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: MetricTile(label: 'Cash with staff', value: formatMoneyCompact(data.cashWithStaffPaise), caption: 'Not yet handed over', icon: Icons.payments_outlined, tone: StatusTone.pending),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: MetricTile(label: 'Pending verification', value: formatMoneyCompact(data.pendingVerificationPaise), caption: '${data.openSettlements} open settlement${data.openSettlements == 1 ? '' : 's'}', icon: Icons.fact_check_outlined, tone: StatusTone.info),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: MetricTile(label: 'Verified', value: formatMoneyCompact(data.verifiedPaise), caption: 'Posted to the ledger', icon: Icons.verified_rounded, tone: StatusTone.success),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: MetricTile(label: 'Variance', value: formatMoneyCompact(data.shortagePaise - data.excessPaise), caption: 'Shortage minus excess', icon: Icons.balance_rounded, tone: data.shortagePaise > 0 ? StatusTone.danger : StatusTone.muted),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            DetailSection(
              title: 'Staff cash balances',
              child: data.staffBalances.isEmpty
                  ? Text('No delivery person has collected cash yet.', style: Theme.of(context).textTheme.bodySmall)
                  : Column(
                      children: [
                        for (final balance in data.staffBalances)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                UserAvatar(name: balance.staffName, size: 36),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(balance.staffName, style: Theme.of(context).textTheme.titleSmall),
                                      Text(
                                        '${balance.staffType == 'OWN' ? 'Own team' : balance.partnerName ?? 'Partner'} • collected ${formatMoney(balance.collectedPaise)} • handed over ${formatMoney(balance.handedOverPaise)}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    MoneyText(paise: balance.cashInCustodyPaise, size: 14),
                                    Text('in custody', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            DetailSection(
              title: 'Settlements awaiting verification',
              trailing: TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
              child: _SettlementList(
                settlements: data.settlements.where((settlement) => settlement.status == 'PENDING_VERIFICATION').toList(),
                onOpen: _showSettlement,
                onConfirm: _confirm,
                onDispute: _dispute,
              ),
            ),
            const SizedBox(height: 18),
            DetailSection(
              title: 'Recent settlements',
              child: _SettlementList(
                settlements: data.settlements.where((settlement) => settlement.status != 'PENDING_VERIFICATION').take(10).toList(),
                onOpen: _showSettlement,
                onConfirm: _confirm,
                onDispute: _dispute,
              ),
            ),
            const SizedBox(height: 18),
            DetailSection(
              title: 'Recent COD ledger entries',
              child: data.recentTransactions.isEmpty
                  ? Text('Ledger entries appear after the first delivery or settlement.', style: Theme.of(context).textTheme.bodySmall)
                  : Column(
                      children: [
                        for (final transaction in data.recentTransactions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: toneBackground(statusTone(transaction.entryType)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.swap_vert_rounded, size: 16, color: toneColor(statusTone(transaction.entryType))),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(statusLabel(transaction.entryType), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5)),
                                      Text(
                                        '${transaction.description ?? 'COD entry'} • ${formatDateTime(transaction.createdAt)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                                MoneyText(paise: transaction.amountPaise, size: 13),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementList extends StatelessWidget {
  const _SettlementList({required this.settlements, required this.onOpen, required this.onConfirm, required this.onDispute});
  final List<CodSettlement> settlements;
  final ValueChanged<CodSettlement> onOpen;
  final ValueChanged<CodSettlement> onConfirm;
  final ValueChanged<CodSettlement> onDispute;

  @override
  Widget build(BuildContext context) {
    if (settlements.isEmpty) {
      return Text('Nothing to show here yet.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(
      children: [
        for (final settlement in settlements)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpen(settlement),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${settlement.settlementNumber} • ${settlement.staffName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5),
                          ),
                        ),
                        StatusBadge(status: settlement.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Declared ${formatMoney(settlement.handedOverPaise)} • ${settlement.itemCount} shipment${settlement.itemCount == 1 ? '' : 's'} • ${relativeTime(settlement.declaredAt)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                          ),
                        ),
                        if (settlement.status == 'PENDING_VERIFICATION') ...[
                          TextButton(onPressed: () => onDispute(settlement), child: const Text('Dispute')),
                          FilledButton(
                            onPressed: () => onConfirm(settlement),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                            child: const Text('Verify'),
                          ),
                        ],
                      ],
                    ),
                    if (settlement.status == 'SETTLED')
                      Text(
                        'Shortage ${formatMoney(settlement.shortagePaise)} • Excess ${formatMoney(settlement.excessPaise)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
