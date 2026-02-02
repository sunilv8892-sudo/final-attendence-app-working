import 'package:flutter/material.dart';

/// Application constants and theming
class AppConstants {
  // App metadata
  static const String appName = 'Face Recognition Attendance';
  static const String appVersion = '1.0.0';
  static const String subtitle = 'Offline Mobile Face Recognition Attendance System Using Face Embedding and Similarity Matching';

  // Colors
  static const Color primaryColor = Color(0xFFFFC107);
  static const Color secondaryColor = Color(0xFF050505);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFFE082);
  static const Color errorColor = Color(0xFFF44336);
  static const Color backgroundColor = Color(0xFF060606);
  static const Color cardColor = Color(0x33FFFFFF);
  static const Color goldButtonColor = Color(0xFFD9A700);
  static const Color inputFill = Color(0x14FFFFFF);
  static const Color dialogBackground = Color(0xD9050505);
  static const Color glassLayer = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x88FFC107);
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF020202),
      Color(0xFF090909),
      Color(0xFF1A0F00),
      Color(0xFF321D00),
      Color(0xFF0A0A0A),
    ],
  );

  // Sizing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double borderRadius = 8.0;
  static const double buttonHeight = 48.0;

  // Face Recognition Settings
  static const double similarityThreshold = 0.50;
  static const int requiredEnrollmentSamples = 15;
  static const int recommendedEnrollmentSamples = 30;
  static const int embeddingDimension = 192;

  // Routes
  static const String routeHome = '/';
  static const String routeEnroll = '/enroll';
  static const String routeAttendance = '/attendance';
  static const String routeDatabase = '/database';
  static const String routeExport = '/export';
  static const String routeSettings = '/settings';

  // Database
  static const String dbName = 'attendance.db';
}

/// App theme configuration
class AppTheme {
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppConstants.primaryColor,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppConstants.cardColor,
      onPrimary: AppConstants.secondaryColor,
      onSurface: Colors.white,
    );
    final baseTextTheme = Typography.whiteCupertino.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppConstants.cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        shadowColor: Colors.black26,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.goldButtonColor,
          foregroundColor: AppConstants.secondaryColor,
          minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppConstants.primaryColor,
          side: const BorderSide(color: AppConstants.primaryColor),
          minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: Colors.white70),
        ),
        contentPadding: const EdgeInsets.all(AppConstants.paddingMedium),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: baseTextTheme.titleLarge?.copyWith(color: AppConstants.primaryColor),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(color: AppConstants.primaryColor),
        labelLarge: baseTextTheme.labelLarge?.copyWith(color: AppConstants.primaryColor),
      ),
      primaryTextTheme: baseTextTheme,
      scaffoldBackgroundColor: AppConstants.backgroundColor,
      canvasColor: AppConstants.backgroundColor,
      dialogTheme: DialogThemeData(
        backgroundColor: AppConstants.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.borderRadius)),
        titleTextStyle: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.bold),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppConstants.primaryColor),
      ),
      tooltipTheme: TooltipThemeData(
        triggerMode: TooltipTriggerMode.longPress,
        textStyle: const TextStyle(color: Colors.white),
        decoration: BoxDecoration(
          color: Colors.black87,
          border: Border.all(color: AppConstants.primaryColor),
          borderRadius: BorderRadius.circular(AppConstants.borderRadius / 2),
        ),
      ),
    );
  }
}
