import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/order_status.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false, this.inverse = false});
  final bool compact;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = inverse ? Colors.white : (dark ? Colors.white : IndiBizzColors.navy);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 34 : 40,
          height: compact ? 34 : 40,
          decoration: BoxDecoration(
            color: inverse ? Colors.white : IndiBizzColors.navy,
            borderRadius: BorderRadius.circular(11),
            boxShadow: inverse
                ? null
                : [
                    BoxShadow(
                      color: IndiBizzColors.navy.withValues(alpha: dark ? 0.4 : 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            'IB',
            style: TextStyle(
              color: inverse ? IndiBizzColors.navy : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 13 : 15,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'IndiaBizz',
                style: TextStyle(
                  color: foreground,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'COMMERCE & DELIVERY',
                style: TextStyle(
                  color: inverse ? Colors.white70 : (dark ? IndiBizzColors.darkInkMuted : IndiBizzColors.inkMuted),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 1180, this.padding});
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Insets.lg),
          child: child,
        ),
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(Insets.lg), this.onTap, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? IndiBizzColors.darkSurface : IndiBizzColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? (dark ? IndiBizzColors.darkBorder : IndiBizzColors.border)),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: content),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.label});
  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = statusTone(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: toneBackground(tone, dark: dark),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? statusLabel(status),
        style: TextStyle(
          color: toneColor(tone, dark: dark),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText({super.key, required this.paise, this.size = 15, this.weight = FontWeight.w700, this.color});
  final int paise;
  final double size;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMoney(paise),
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone = StatusTone.info,
    this.onTap,
  });
  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final StatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = toneColor(tone, dark: dark);
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: toneBackground(tone, dark: dark), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon ?? Icons.insights_rounded, size: 17, color: accent),
              ),
              const Spacer(),
              if (onTap != null) Icon(Icons.arrow_outward_rounded, size: 15, color: theme.textTheme.bodySmall?.color),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(fontSize: 24, letterSpacing: -0.6),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5)),
          ],
        ],
      ),
    );
  }
}

class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.title,
    this.tone = StatusTone.info,
    this.icon,
    this.action,
  });
  final String message;
  final String? title;
  final StatusTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = toneColor(tone, dark: dark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: toneBackground(tone, dark: dark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _noticeIcon(tone), size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                ],
                Text(message, style: TextStyle(fontSize: 12.5, height: 1.45, color: dark ? IndiBizzColors.darkInk : IndiBizzColors.ink)),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _noticeIcon(StatusTone tone) {
    switch (tone) {
      case StatusTone.success:
        return Icons.check_circle_outline_rounded;
      case StatusTone.danger:
        return Icons.error_outline_rounded;
      case StatusTone.pending:
        return Icons.schedule_rounded;
      case StatusTone.info:
        return Icons.info_outline_rounded;
      case StatusTone.muted:
        return Icons.notes_rounded;
    }
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(height: 14),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inventory_2_outlined,
    this.action,
  });
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.canvas,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 25, color: dark ? IndiBizzColors.darkInkMuted : IndiBizzColors.inkMuted),
            ),
            const SizedBox(height: 15),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 330),
              child: Text(message, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _clean(error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 34, color: IndiBizzColors.danger),
            const SizedBox(height: 13),
            Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 17), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }

  String _clean(Object value) {
    final text = value.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (text.contains('PostgrestException')) return text.replaceFirst('PostgrestException(message: ', '').split(', code:').first;
    return text;
  }
}

typedef AsyncBuilder<T> = Widget Function(BuildContext context, T data);

class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.builder,
    this.loadingLabel = 'Loading…',
    this.isEmpty,
    this.emptyBuilder,
    this.padding = EdgeInsets.zero,
  });

  final Future<T> Function() load;
  final AsyncBuilder<T> builder;
  final String loadingLabel;
  final bool Function(T)? isEmpty;
  final Widget Function(BuildContext)? emptyBuilder;
  final EdgeInsetsGeometry padding;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _reload() => setState(() => _future = widget.load());

  @override
  void didUpdateWidget(covariant AsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(padding: widget.padding, child: LoadingView(label: widget.loadingLabel));
        }
        if (snapshot.hasError) {
          return Padding(
            padding: widget.padding,
            child: ErrorView(error: snapshot.error!, onRetry: _reload),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return Padding(padding: widget.padding, child: LoadingView(label: widget.loadingLabel));
        }
        if (widget.isEmpty?.call(data) ?? false) {
          return Padding(
            padding: widget.padding,
            child: widget.emptyBuilder?.call(context) ??
                const EmptyView(title: 'Nothing here yet', message: 'New activity will appear here.'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: widget.builder(context, data),
        );
      },
    );
  }
}

Future<void> showToast(BuildContext context, String message, {bool error = false}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? IndiBizzColors.danger : null,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: IndiBizzColors.danger) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initialValue,
  String confirmLabel = 'Save',
  String? helper,
  int maxLines = 1,
  bool required = true,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint, helperText: helper),
          validator: required
              ? (value) => (value == null || value.trim().isEmpty) ? 'This field is required.' : null
              : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<void> copyText(BuildContext context, String value, {String? label}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) showToast(context, '${label ?? 'Copied'} copied to clipboard.');
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.valueColor, this.trailing});
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: 12),
          if (trailing != null) trailing! else Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: valueColor ?? theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 42});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.navy,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials(name),
        style: TextStyle(
          color: dark ? IndiBizzColors.darkInk : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, this.hint = 'Search…', this.onChanged, this.onSubmitted});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 17),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
      ),
    );
  }
}

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({super.key, required this.values, required this.selected, required this.labelFor, required this.onSelected});
  final List<String?> values;
  final String? selected;
  final String Function(String?) labelFor;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final value in values) ...[
            ChoiceChip(
              label: Text(labelFor(value)),
              selected: selected == value,
              onSelected: (_) => onSelected(value),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}
