import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

const deliveryPagePadding = EdgeInsets.fromLTRB(16, 16, 16, 24);

/// Runs a delivery staff action, handles errors gracefully and surfaces them verbatim.
Future<bool> runStaffAction(
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
    showToast(context, cleanErrorMessage(error), error: true);
    return false;
  }
}

String cleanErrorMessage(Object error) {
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'No internet connection. Please check your data connection.';
  }
  return text.replaceFirst('PostgrestException(message: ', '').split(', code:').first;
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
              if (trailing != null) trailing!,
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
  const Tag({super.key, required this.text, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: dark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: baseColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: baseColor), const SizedBox(width: 4)],
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: baseColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
