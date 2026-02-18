import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Primary palette (Indigo / Cyan)
  static const Color primary = Color(0xFF3F51B5); // Indigo 500
  static const Color primaryVariant = Color(0xFF303F9F); // Indigo 700
  static const Color secondary = Color(0xFF00BCD4); // Cyan 500
  static const Color accent = Color(0xFF00ACC1); // Cyan accent

  // UI neutrals
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF57C00);
  static const Color error = Color(0xFFD32F2F);
}

class AppTheme {
  AppTheme._();

  static final ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    error: AppColors.error,
    onError: Colors.white,
    background: AppColors.background,
    onBackground: Colors.black87,
    surface: AppColors.surface,
    onSurface: Colors.black87,
  );

  static ThemeData get lightTheme {
    final base = ThemeData.from(colorScheme: _lightScheme);
    return base.copyWith(
      useMaterial3: false,
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      primaryColor: _lightScheme.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: _lightScheme.primary.withOpacity(0.95),
        foregroundColor: _lightScheme.onPrimary,
        elevation: 2,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightScheme.primary,
          foregroundColor: _lightScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightScheme.primary,
          side: BorderSide(color: _lightScheme.primary.withOpacity(0.85)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightScheme.primary,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
      ),
    );
  }
}
