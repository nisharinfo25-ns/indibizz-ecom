/// Compile-time configuration shared by every IndiaBizz application.
///
/// Supply values at build time:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const appName = 'IndiaBizz';
  static const supportEmail = 'support@indibizz.in';
  static const currencyLocale = 'en_IN';
  static const timeZone = 'Asia/Kolkata';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
