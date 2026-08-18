import 'package:flutter/material.dart';

/// Charleston School of Law visual identity.
///
/// The palette is anchored on the same deep navy the admin portal uses
/// (#1E3C72), so the scanner app and the portal read as one product family.
/// The look is modern Material 3: flat surfaces, generous corner radii,
/// tonal fills instead of drop shadows, and large friendly type.
class AppTheme {
  // Brand
  static const Color navy = Color(0xFF1E3C72);
  static const Color navyLight = Color(0xFF2A5298);
  static const Color gold = Color(0xFFC9A227);
  static const Color successGreen = Color(0xFF2E9E5B);
  static const Color errorRed = Color(0xFFDC2626);
  static const Color warningOrange = Color(0xFFF59E0B);

  // Legacy aliases still referenced around the codebase.
  static const Color primaryBlue = navy;
  static const Color secondaryGreen = successGreen;
  static const Color accentGold = gold;
  static const Color darkGray = Color(0xFF1F2937);
  static const Color mediumGray = Color(0xFF6B7280);
  static const Color lightGray = Color(0xFFF8FAFC);
  static const Color white = Color(0xFFFFFFFF);

  static const double _radius = 16;

  static RoundedRectangleBorder get _shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: brightness,
      primary: brightness == Brightness.light ? navy : navyLight,
      secondary: successGreen,
      tertiary: gold,
      error: errorRed,
    );

    final isLight = brightness == Brightness.light;
    final surface = isLight ? white : const Color(0xFF111827);
    final background = isLight ? lightGray : const Color(0xFF0B1220);
    final onSurface = isLight ? darkGray : const Color(0xFFF3F4F6);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: surface, onSurface: onSurface),
      scaffoldBackgroundColor: background,

      // Flat, contemporary app bar: no solid brand block, no shadow.
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: onSurface,
        ),
      ),

      // Cards float on tone, not shadow.
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(
            color: isLight
                ? const Color(0xFFE5E7EB)
                : const Color(0xFF374151),
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: _shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: _shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: _shape,
          side: BorderSide(color: scheme.primary, width: 1.5),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: _shape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 4,
      ),

      // Soft filled inputs instead of outlined boxes.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1F2937),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: errorRed, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconColor: scheme.primary,
      ),

      dividerTheme: DividerThemeData(
        color: isLight ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
        thickness: 1,
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: onSurface),
        headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: onSurface),
        headlineSmall: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, color: onSurface),
        titleLarge: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w600, color: onSurface),
        titleMedium: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, color: onSurface),
        titleSmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isLight ? mediumGray : const Color(0xFF9CA3AF)),
        bodyLarge: TextStyle(fontSize: 17, height: 1.4, color: onSurface),
        bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: onSurface),
        bodySmall: TextStyle(
            fontSize: 13,
            color: isLight ? mediumGray : const Color(0xFF9CA3AF)),
        labelLarge: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: onSurface),
      ),
    );
  }

  static ThemeData get lightTheme => _base(Brightness.light);
  static ThemeData get darkTheme => _base(Brightness.dark);
}
