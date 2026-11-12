import 'package:indibizz_core/indibizz_core.dart';
import 'package:material_ui/material_ui.dart';

const customerPagePadding = EdgeInsets.fromLTRB(16, 16, 16, 24);

Future<bool> runCustomerAction(
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

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.imageUrl,
    this.width = 72,
    this.height = 72,
    this.borderRadius = 8,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.neutral100,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.image_outlined,
        color: dark ? IndiBizzColors.darkBorder : IndiBizzColors.neutral400,
        size: width * 0.4,
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        imageUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
