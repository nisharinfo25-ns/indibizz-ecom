import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth/auth_controller.dart';
import 'src/config/app_config.dart';
import 'src/theme/app_theme.dart';

export 'src/api/api_client.dart';
export 'src/auth/auth_controller.dart';
export 'src/config/app_config.dart';
export 'src/models/models.dart';
export 'src/repositories/customer_repository.dart';
export 'src/repositories/owner_repository.dart';
export 'src/repositories/partner_repository.dart';
export 'src/repositories/staff_repository.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/theme_controller.dart';
export 'src/utils/formatters.dart';
export 'src/utils/order_status.dart';
export 'src/widgets/auth_gate.dart';
export 'src/widgets/common.dart';
export 'src/widgets/shell.dart';

/// Single entry point used by the three Flutter applications.
class IndiBizz {
  IndiBizz._();

  static Future<void> initialize({String? supabaseUrl, String? anonKey}) async {
    final url = supabaseUrl ?? AppConfig.supabaseUrl;
    final key = anonKey ?? AppConfig.supabaseAnonKey;
    if (url.isEmpty || key.isEmpty) {
      throw const AppConfigurationException(
        'SUPABASE_URL and SUPABASE_ANON_KEY are missing. Pass them with '
        '--dart-define or run with a configured .env file.',
      );
    }
    await Supabase.initialize(url: url, publishableKey: key);
  }

  static SupabaseClient get client => Supabase.instance.client;

  static AuthController authController() => AuthController(client);
}

/// Kept here so consumers can share one storage upload routine.
class StorageUploads {
  StorageUploads._();

  static Future<String> uploadEvidence({
    required String orderId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$orderId/${DateTime.now().microsecondsSinceEpoch}-$safe';
    await IndiBizz.client.storage
        .from('return-evidence')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
    return path;
  }

  static Future<String> uploadDeliveryPhoto({
    required String shipmentId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$shipmentId/${DateTime.now().microsecondsSinceEpoch}-$safe';
    await IndiBizz.client.storage
        .from('delivery-proofs')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
    return path;
  }

  static Future<String> uploadProductImage({
    required String productId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$productId/${DateTime.now().microsecondsSinceEpoch}-$safe';
    await IndiBizz.client.storage
        .from('product-images')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
    return path;
  }

  static Future<String?> signedUrl(String bucket, String? path, {int seconds = 3600}) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await IndiBizz.client.storage.from(bucket).createSignedUrl(path, seconds);
    } catch (_) {
      return null;
    }
  }
}

/// Convenience theme access mirrors Material conventions.
class AppTheme {
  static ThemeData get light => IndiBizzTheme.light();
  static ThemeData get dark => IndiBizzTheme.dark();
}

/// The exception shown when required build-time configuration is absent.
class AppConfigurationException implements Exception {
  const AppConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Re-export Material so applications only need this package.
const MaterialColor brandNavy = IndiBizzColors.navy;
