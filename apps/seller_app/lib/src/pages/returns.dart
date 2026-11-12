import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui.dart';
import 'orders.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key, required this.repository});
  final OwnerRepository repository;

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  String? _status;
  int _revision = 0;

  static const _statuses = <String?>[null, 'REQUESTED', 'APPROVED', 'REJECTED', 'RECEIVED', 'CLOSED'];

  Future<void> _decide(ReturnAdmin item, bool approve) async {
    String? note;
    if (approve) {
      note = await promptText(
        context,
        title: 'Approve return',
        hint: 'Resolution note (optional)',
        required: false,
        maxLines: 2,
        confirmLabel: 'Approve',
      );
    } else {
      note = await askReason(context, title: 'Reject return', hint: 'Why is this return being rejected?', confirmLabel: 'Reject return');
    }
    if (note == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.decideReturn(returnId: item.id, approve: approve, note: note!.isEmpty ? null : note),
      success: approve ? 'Return approved.' : 'Return rejected.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _markReceived(ReturnAdmin item) async {
    final ok = await confirmAction(
      context,
      title: 'Mark return received',
      message: 'Confirm that the physical item is back in your custody. This is final evidence for the return.',
      confirmLabel: 'Mark received',
    );
    if (!ok || !mounted) return;
    final success = await runSellerAction(context, () => widget.repository.markReturnReceived(item.id), success: 'Return marked received.');
    if (success && mounted) setState(() => _revision++);
  }

  Future<void> _close(ReturnAdmin item) async {
    final note = await promptText(
      context,
      title: 'Close return',
      hint: 'Closing note (optional)',
      required: false,
      maxLines: 2,
      confirmLabel: 'Close return',
    );
    if (note == null || !mounted) return;
    final ok = await runSellerAction(
      context,
      () => widget.repository.closeReturn(item.id, note: note.isEmpty ? null : note),
      success: 'Return closed.',
    );
    if (ok && mounted) setState(() => _revision++);
  }

  Future<void> _openEvidence(ReturnAdmin item) async {
    if (item.evidencePath == null) return;
    try {
      final url = await widget.repository.signedReturnEvidence(item.evidencePath);
      if (url == null) throw Exception('The evidence file could not be signed.');
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open the evidence file.');
    } catch (error) {
      if (mounted) showToast(context, error.toString(), error: true);
    }
  }

  void _showDetails(ReturnAdmin item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text(item.returnNumber, style: Theme.of(context).textTheme.titleLarge)),
                StatusBadge(status: item.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('Order ${item.orderNumber} • ${item.customerName} • ${formatDateTime(item.createdAt, includeYear: true)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            DetailSection(
              title: 'Customer reason',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.reason, style: Theme.of(context).textTheme.titleSmall),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.description, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (item.evidencePath != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(onPressed: () => _openEvidence(item), icon: const Icon(Icons.image_outlined, size: 16), label: const Text('Open evidence')),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Returned items',
              child: item.items.isEmpty
                  ? Text('No item lines were returned.', style: Theme.of(context).textTheme.bodySmall)
                  : Column(
                      children: [
                        for (final line in item.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(line.productName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12.5)),
                                      Text('${line.sku} • quantity ${line.quantity}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5)),
                                    ],
                                  ),
                                ),
                                MoneyText(paise: line.lineTotalPaise, size: 13),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            DetailSection(
              title: 'Timeline',
              child: Column(
                children: [
                  KeyValueRow(label: 'Delivered', value: formatDateTime(item.deliveredAt, includeYear: true)),
                  KeyValueRow(label: 'Requested', value: formatDateTime(item.createdAt, includeYear: true)),
                  if (item.decidedAt != null) KeyValueRow(label: 'Decided', value: formatDateTime(item.decidedAt, includeYear: true)),
                  if (item.receivedAt != null) KeyValueRow(label: 'Received', value: formatDateTime(item.receivedAt, includeYear: true)),
                  if (item.closedAt != null) KeyValueRow(label: 'Closed', value: formatDateTime(item.closedAt, includeYear: true)),
                  if (item.rejectionReason != null) KeyValueRow(label: 'Rejection reason', value: item.rejectionReason!),
                  if (item.resolutionNote != null) KeyValueRow(label: 'Resolution note', value: item.resolutionNote!),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(onPressed: () => openAdminOrder(context, widget.repository, item.orderId), icon: const Icon(Icons.receipt_long_outlined, size: 16), label: const Text('Open order')),
                if (item.status == 'REQUESTED') ...[
                  FilledButton.icon(onPressed: () => _decide(item, true), icon: const Icon(Icons.check_rounded, size: 16), label: const Text('Approve')),
                  OutlinedButton.icon(onPressed: () => _decide(item, false), icon: const Icon(Icons.close_rounded, size: 16), label: const Text('Reject'), style: OutlinedButton.styleFrom(foregroundColor: IndiBizzColors.danger)),
                ],
                if (item.status == 'APPROVED')
                  FilledButton.icon(onPressed: () => _markReceived(item), icon: const Icon(Icons.inventory_outlined, size: 16), label: const Text('Mark received')),
                if (item.status == 'RECEIVED')
                  FilledButton.icon(onPressed: () => _close(item), icon: const Icon(Icons.done_all_rounded, size: 16), label: const Text('Close return')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChipRow(
              values: _statuses,
              selected: _status,
              labelFor: (value) => value == null ? 'All' : statusLabel(value),
              onSelected: (value) => setState(() {
                _status = value;
                _revision++;
              }),
            ),
          ),
        ),
        Expanded(
          child: OwnerAsyncPage<List<ReturnAdmin>>(
            key: ValueKey('returns-$_revision'),
            scrollable: true,
            load: () => widget.repository.listReturns(status: _status),
            loadingLabel: 'Loading returns…',
            emptyTitle: 'No return requests',
            emptyMessage: 'Delivered orders can be returned from the customer app or website. Requests appear here.',
            emptyIcon: Icons.assignment_return_outlined,
            isEmpty: (data) => data.isEmpty,
            builder: (context, returns, refresh) => sellerList([
              Row(
                children: [
                  Expanded(child: Text('${returns.length} return${returns.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Refresh')),
                ],
              ),
              const SizedBox(height: 4),
              for (final item in returns)
                OrderCardShell(
                  borderColor: item.status == 'REQUESTED' ? IndiBizzColors.warning : null,
                  onTap: () => _showDetails(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(item.returnNumber, style: Theme.of(context).textTheme.titleSmall)),
                          StatusBadge(status: item.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${item.orderNumber} • ${item.customerName}', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 7),
                      Text(item.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Tag(text: formatMoney(item.orderTotalPaise), icon: Icons.receipt_outlined),
                          Tag(text: relativeTime(item.createdAt), icon: Icons.schedule_rounded),
                          if (item.evidencePath != null) const Tag(text: 'Evidence attached', icon: Icons.attachment_rounded),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (item.status == 'REQUESTED') ...[
                            FilledButton(
                              onPressed: () => _decide(item, true),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: const Text('Approve'),
                            ),
                            OutlinedButton(
                              onPressed: () => _decide(item, false),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: const Text('Reject'),
                            ),
                          ],
                          if (item.status == 'APPROVED')
                            FilledButton(
                              onPressed: () => _markReceived(item),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: const Text('Mark received'),
                            ),
                          if (item.status == 'RECEIVED')
                            FilledButton(
                              onPressed: () => _close(item),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: const Text('Close'),
                            ),
                          TextButton(onPressed: () => _showDetails(item), child: const Text('Details')),
                        ],
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}
