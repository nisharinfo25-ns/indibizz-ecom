import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

const sellerPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);

/// Runs a business action, surfaces failures verbatim and returns whether the
/// caller should reload. Business rules live in Postgres; the UI never hides
/// them behind a fake success.
Future<bool> runSellerAction(
  BuildContext context,
  Future<Object?> Function() action, {
  required String success,
}) async {
  try {
    await action();
    if (!context.mounted) return true;
    showToast(context, success);
    return true;
  } catch (error) {
    if (!context.mounted) return false;
    showToast(context, _cleanError(error), error: true);
    return false;
  }
}

String _cleanError(Object error) {
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'No internet connection. Check your network and try again.';
  }
  return text.replaceFirst('PostgrestException(message: ', '').split(', code:').first;
}

Future<String?> askReason(
  BuildContext context, {
  required String title,
  String hint = 'Explain the reason',
  String confirmLabel = 'Confirm',
}) =>
    promptText(context, title: title, hint: hint, confirmLabel: confirmLabel, maxLines: 3);

class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.child, this.padding = sellerPagePadding});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: child,
    );
  }
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag({super.key, required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.canvas,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Theme.of(context).textTheme.bodySmall?.color), const SizedBox(width: 4)],
          Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class OrderCardShell extends StatelessWidget {
  const OrderCardShell({super.key, required this.child, this.onTap, this.borderColor});
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SurfaceCard(onTap: onTap, borderColor: borderColor, padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class OwnerAsyncPage<T> extends StatefulWidget {
  const OwnerAsyncPage({
    super.key,
    required this.load,
    required this.builder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.isEmpty,
    this.padding = sellerPagePadding,
    this.loadingLabel = 'Loading…',
    this.scrollable = false,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback refresh) builder;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final bool Function(T data)? isEmpty;
  final EdgeInsetsGeometry padding;
  final String loadingLabel;
  final bool scrollable;

  @override
  State<OwnerAsyncPage<T>> createState() => _OwnerAsyncPageState<T>();
}

class _OwnerAsyncPageState<T> extends State<OwnerAsyncPage<T>> {
  late Future<T> _future;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _refresh() {
    setState(() {
      _revision++;
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      key: ValueKey(_revision),
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(padding: widget.padding, child: LoadingView(label: widget.loadingLabel));
        }
        if (snapshot.hasError) {
          return SingleChildScrollView(
            padding: widget.padding,
            child: ErrorView(error: snapshot.error!, onRetry: _refresh),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Padding(padding: widget.padding, child: LoadingView(label: widget.loadingLabel));
        }
        if (widget.isEmpty?.call(data) ?? false) {
          return SingleChildScrollView(
            padding: widget.padding,
            child: EmptyView(title: widget.emptyTitle, message: widget.emptyMessage, icon: widget.emptyIcon),
          );
        }
        final content = widget.builder(context, data, _refresh);
        if (widget.scrollable) {
          return RefreshIndicator(onRefresh: () async => _refresh(), child: content);
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            child: content,
          ),
        );
      },
    );
  }
}

/// A scrollable, refreshable list with consistent padding.
Widget sellerList(List<Widget> children) {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: sellerPagePadding,
    children: children,
  );
}
