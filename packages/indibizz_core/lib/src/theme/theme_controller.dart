import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the light/dark preference locally. The preference is a device
/// concern, so it never travels to the backend.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._mode);

  static final ThemeController instance = ThemeController._(ThemeMode.system);
  static const _preferenceKey = 'indibizz.theme_mode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_preferenceKey);
      final parsed = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (parsed != _mode) {
        _mode = parsed;
        notifyListeners();
      }
    } catch (_) {
      // A missing local preference store must never block the application.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _preferenceKey,
        switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (_) {
      // The in-memory preference still applies for this session.
    }
  }

  /// Toggles between explicit light and dark. When following the system, the
  /// first toggle chooses the opposite of the currently rendered brightness.
  Future<void> toggle(Brightness current) async {
    final next = switch (_mode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    };
    await setMode(next);
  }
}
