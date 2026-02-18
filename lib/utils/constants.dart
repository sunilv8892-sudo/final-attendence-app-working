import 'package:flutter/material.dart';

/// Application constants and theming
class AppConstants {
  // App metadata
  static const String appName = 'Face Recognition Attendance';
  static const String appVersion = '1.0.0';
  static const String subtitle =
      'Offline Mobile Face Recognition Attendance System Using Face Embedding and Similarity Matching';

  // Colors - Glassmorphism Theme
  static const Color primaryColor = Color(0xFF00695C);      // Teal 800
  static const Color primaryDark = Color(0xFF004D40);       // Teal 900
  static const Color primaryLight = Color(0xFF26A69A);      // Teal 400
  static const Color accentColor = Color(0xFFFFC107);       // Amber 500
  static const Color accentDark = Color(0xFFFFA000);        // Amber 700
  
  static const Color secondaryColor = Color(0xFF0F0C29);    // Midnight
  static const Color surfaceColor = Color(0xFF1A1A2E);      // Night Surface
  
  static const Color successColor = Color(0xFF10B981);      // Emerald
  static const Color successLight = Color(0xFF34D399);      // Light Emerald
  static const Color warningColor = Color(0xFFF59E0B);      // Amber
  static const Color errorColor = Color(0xFFEF4444);        // Red
  static const Color errorLight = Color(0xFFF87171);        // Light Red
  
  static const Color backgroundColor = Color(0xFF0F0C29);   // Deep Midnight
  static const Color cardColor = Color(0xFF1A1A2E);         // Card Surface
  static const Color cardBorder = Color(0x33FFFFFF);         // Glass Border
  
  static const Color textPrimary = Color(0xFFF1F5F9);       // Near White
  static const Color textSecondary = Color(0xFF94A3B8);     // Cool Gray
  static const Color textTertiary = Color(0xFF64748B);      // Slate
  
  static const Color inputFill = Color(0xFF16213E);         // Dark Blue
  static const Color inputBorder = Color(0x33FFFFFF);       // Glass Border
  
  static const Color dividerColor = Color(0x1AFFFFFF);      // White 10%
  
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0F0C29),
      Color(0xFF302B63),
      Color(0xFF24243E),
    ],
  );
  
  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00695C),
      Color(0xFF00897B),
      Color(0xFF004D40),
    ],
  );
  
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF06B6D4),
      Color(0xFF0891B2),
    ],
  );

  // Glass effect constants
  static const double glassOpacity = 0.08;
  static const double glassBorderOpacity = 0.15;
  static const double glassBlur = 12.0;

  // Sizing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingExtraLarge = 32.0;
  
  static const double borderRadius = 12.0;
  static const double borderRadiusLarge = 16.0;
  
  static const double buttonHeight = 52.0;
  static const double buttonHeightSmall = 40.0;
  
  // Shadows
  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x40000000),
    blurRadius: 24.0,
    offset: Offset(0, 8),
  );
  
  static const BoxShadow buttonShadow = BoxShadow(
    color: Color(0x407C6CF6),
    blurRadius: 20.0,
    offset: Offset(0, 8),
  );

  // Face Recognition Settings
  static const double similarityThreshold = 0.75;
  static const int requiredEnrollmentSamples = 10;  // 10 samples for enrollment
  static const int recommendedEnrollmentSamples = 15;
  static const int embeddingDimension = 192;

  // Routes
  static const String routeHome = '/';
  static const String routeEnroll = '/enroll';
  static const String routeAttendance = '/attendance';
  static const String routeDatabase = '/database';
  static const String routeExport = '/export';
  static const String routeSettings = '/settings';
  static const String routeExpressionDetection = '/expression_detection';

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
      primary: AppConstants.primaryColor,
      surface: AppConstants.cardColor,
      onPrimary: Colors.white,
      onSurface: AppConstants.textPrimary,
    );
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppConstants.backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: AppConstants.secondaryColor,
        foregroundColor: AppConstants.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: AppConstants.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppConstants.cardColor,
        elevation: 4,
        shadowColor: AppConstants.cardShadow.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          side: const BorderSide(color: AppConstants.cardBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: AppConstants.buttonShadow.color,
          minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppConstants.primaryColor,
          side: const BorderSide(color: AppConstants.primaryColor, width: 2),
          minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.primaryColor,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.paddingMedium,
          vertical: AppConstants.paddingMedium,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: AppConstants.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: AppConstants.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(
            color: AppConstants.primaryColor,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: AppConstants.errorColor),
        ),
        hintStyle: const TextStyle(
          color: AppConstants.textTertiary,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          color: AppConstants.textSecondary,
          fontSize: 14,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppConstants.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppConstants.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppConstants.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppConstants.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: AppConstants.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppConstants.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppConstants.textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppConstants.primaryColor,
        unselectedLabelColor: AppConstants.textTertiary,
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppConstants.primaryColor,
              width: 3,
            ),
          ),
        ),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 14,
        ),
      ),
      dividerColor: AppConstants.dividerColor,
      dividerTheme: const DividerThemeData(
        color: AppConstants.dividerColor,
        thickness: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppConstants.primaryColor,
        inactiveTrackColor: AppConstants.inputFill,
        thumbColor: AppConstants.primaryColor,
        overlayColor: AppConstants.primaryColor.withAlpha(64),
        valueIndicatorColor: AppConstants.primaryColor,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      canvasColor: AppConstants.backgroundColor,
      dialogTheme: DialogThemeData(
        backgroundColor: AppConstants.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        ),
        titleTextStyle: const TextStyle(
          color: AppConstants.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        contentTextStyle: const TextStyle(
          color: AppConstants.textSecondary,
          fontSize: 14,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        triggerMode: TooltipTriggerMode.longPress,
        textStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A).withAlpha(230),
          border: Border.all(color: AppConstants.primaryColor, width: 1),
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          boxShadow: [AppConstants.cardShadow],
        ),
      ),
    );
  }
}

// Feature-specific color themes
class ColorSchemes {
  // Status colors for attendance
  static const Color presentColor = Color(0xFF4CAF50);
  static const Color absentColor = Color(0xFFE53935);
  static const Color lateColor = Color(0xFFFFA726);
  static const Color pendingColor = Color(0xFF1E88E5);
}
