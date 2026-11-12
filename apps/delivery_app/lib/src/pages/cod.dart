import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

import '../ui.dart';

class CodPage extends StatefulWidget {
  const CodPage({super.key, required this.repository});
  final StaffRepository repository;

  @override
  State<CodPage> createState() => _CodPageState();
}

class _CodPageState extends State<CodPage> {
  StaffCodSummary? _summary;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.repository.codSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  Future<void> _declareHandover() async {
    final noteCtrl = TextEditingController();

    final declared = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Declare Cash Handover'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are declaring handover of all cash in your custody (${formatMoney(_summary!.cashInCustodyPaise)}) to the cashier, hub manager or partner office.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Handover Note (Optional)',
                hintText: 'Handed over to cashier John at South Hub',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Declare Handover'),
          ),
        ],
      ),
    );

    if (declared == true && mounted) {
      final ok = await runStaffAction(
        context,
        () => widget.repository.declareCashHandover(
          note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
        ),
        success: 'Cash handover declared! Cashier must verify and accept.',
      );
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return const Center(child: LoadingView(label: 'Loading cash ledger…'));
    }
    if (_error != null && _summary == null) {
      return ErrorNotice(
        title: 'Could not load COD summary',
        error: _error.toString(),
        onRetry: _load,
      );
    }
    final s = _summary!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: deliveryPagePadding,
        children: [
          // Cash in custody hero card
          SurfaceCard(
            color: IndiBizzColors.primary.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Cash in Your Custody',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Icon(Icons.account_balance_wallet_rounded, color: IndiBizzColors.primary),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney(s.cashInCustodyPaise),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: IndiBizzColors.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.cashInCustodyPaise > 0
                      ? 'Physical currency collected from delivered COD orders.'
                      : 'All collected cash has been handed over and settled.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: s.cashInCustodyPaise > 0 ? _declareHandover : null,
                    icon: const Icon(Icons.handshake_rounded),
                    label: const Text('Declare Cash Handover to Hub / Cashier'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Pending settlements section
          if (s.pendingSettlements.isNotEmpty) ...[
            Text('Pending Cashier Verifications', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...s.pendingSettlements.map((settlement) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded, color: IndiBizzColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settlement.settlementNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Declared ${formatDate(settlement.declaredAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Tag(
                        text: 'Awaiting Hub Verification',
                        color: IndiBizzColors.warning,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatMoney(settlement.handedOverPaise),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
          ],

          // Unsettled shipments section
          Text('Unsettled COD Shipments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (s.unsettledShipments.isEmpty)
            const SurfaceCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No unsettled COD shipments in your custody.'),
                ),
              ),
            )
          else
            ...s.unsettledShipments.map((shipment) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: IndiBizzColors.neutral600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shipment.shipmentNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Order: ${shipment.orderNumber}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(shipment.collectedPaise),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: IndiBizzColors.success),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // Recent settlements section
          if (s.recentSettlements.isNotEmpty) ...[
            Text('Recent Settlements History', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...s.recentSettlements.map((settlement) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: IndiBizzColors.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settlement.settlementNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Verified ${formatDate(settlement.verifiedAt ?? settlement.declaredAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Tag(
                        text: settlement.status,
                        color: IndiBizzColors.success,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatMoney(settlement.handedOverPaise),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
