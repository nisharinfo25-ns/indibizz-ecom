import 'package:material_ui/material_ui.dart';

/// IndiaBizz premium white/navy design tokens.
class IndiBizzColors {
  IndiBizzColors._();

  static const MaterialColor navy = MaterialColor(0xFF0B1F3A, <int, Color>{
    50: Color(0xFFEFF2F7),
    100: Color(0xFFD9E0EC),
    200: Color(0xFFB3C1D7),
    300: Color(0xFF8197B8),
    400: Color(0xFF4F6C96),
    500: Color(0xFF2C4C78),
    600: Color(0xFF17365F),
    700: Color(0xFF0B1F3A),
    800: Color(0xFF08182C),
    900: Color(0xFF050F1D),
  });

  static const Color gold = Color(0xFFB98A3E);
  static const Color goldSoft = Color(0xFFF1E3C8);
  static const Color ink = Color(0xFF0B1F3A);
  static const Color inkMuted = Color(0xFF5C6B7F);
  static const Color canvas = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE3E8EF);
  static const Color success = Color(0xFF1D7A4D);
  static const Color successSoft = Color(0xFFE3F4EA);
  static const Color warning = Color(0xFF9A6700);
  static const Color warningSoft = Color(0xFFFFF4D6);
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFDE8E6);
  static const Color info = Color(0xFF175CD3);
  static const Color infoSoft = Color(0xFFE7EFFD);

  static const Color darkCanvas = Color(0xFF071322);
  static const Color darkSurface = Color(0xFF0D1C30);
  static const Color darkSurfaceAlt = Color(0xFF12243A);
  static const Color darkBorder = Color(0xFF22364F);
  static const Color darkInk = Color(0xFFF2F6FB);
  static const Color darkInkMuted = Color(0xFF9EB0C5);

  static const Color lightCanvas = canvas;
}

class IndiBizzTheme {
  IndiBizzTheme._();

  static ThemeData light() => _build(false);
  static ThemeData dark() => _build(true);

  static ThemeData _build(bool dark) {
    final scheme = dark
        ? const ColorScheme.dark(
            primary: Color(0xFF8FB3E8),
            onPrimary: Color(0xFF071322),
            secondary: Color(0xFFD9B36A),
            onSecondary: Color(0xFF251A05),
            surface: IndiBizzColors.darkSurface,
            onSurface: IndiBizzColors.darkInk,
            error: Color(0xFFFF8A80),
            onError: Color(0xFF2B0906),
            outline: IndiBizzColors.darkBorder,
          )
        : const ColorScheme.light(
            primary: IndiBizzColors.navy,
            onPrimary: Colors.white,
            secondary: IndiBizzColors.gold,
            onSecondary: Colors.white,
            surface: IndiBizzColors.surface,
            onSurface: IndiBizzColors.ink,
            error: IndiBizzColors.danger,
            onError: Colors.white,
            outline: IndiBizzColors.border,
          );

    final background = dark ? IndiBizzColors.darkCanvas : IndiBizzColors.canvas;
    final surface = dark ? IndiBizzColors.darkSurface : IndiBizzColors.surface;
    final border = dark ? IndiBizzColors.darkBorder : IndiBizzColors.border;
    final muted = dark ? IndiBizzColors.darkInkMuted : IndiBizzColors.inkMuted;

    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    TextStyle title(double size, {FontWeight weight = FontWeight.w700, Color? color}) => TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color ?? (dark ? IndiBizzColors.darkInk : IndiBizzColors.ink),
          height: 1.18,
          letterSpacing: size > 26 ? -0.8 : -0.2,
        );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: title(44, weight: FontWeight.w800),
        displayMedium: title(36, weight: FontWeight.w800),
        displaySmall: title(30, weight: FontWeight.w800),
        headlineLarge: title(28),
        headlineMedium: title(24),
        headlineSmall: title(21),
        titleLarge: title(18),
        titleMedium: title(15.5, weight: FontWeight.w600),
        titleSmall: title(13.5, weight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 15.5, height: 1.55, color: scheme.onSurface),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurface),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: scheme.onSurface),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0.5,
        shadowColor: border,
        titleTextStyle: title(19),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? IndiBizzColors.darkSurfaceAlt : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        labelStyle: TextStyle(color: muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? IndiBizzColors.darkSurfaceAlt : IndiBizzColors.canvas,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: muted,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: title(19),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? IndiBizzColors.darkInk : IndiBizzColors.ink,
        contentTextStyle: TextStyle(color: dark ? IndiBizzColors.ink : Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? const Color(0xFF233B58) : const Color(0xFFE9EEF5),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(size: 22, color: selected ? scheme.primary : muted);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: dark ? const Color(0xFF233B58) : const Color(0xFFE9EEF5),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
        unselectedLabelTextStyle: TextStyle(fontSize: 12, color: muted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: border),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? IndiBizzColors.darkInk : IndiBizzColors.ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: dark ? IndiBizzColors.ink : Colors.white, fontSize: 12),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}

/// Spacing constants keep the three apps visually consistent.
class Insets {
  Insets._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}
