import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
class AppColors {
  AppColors._();

  // Primary & Accent (unchanged names)
  static const Color primaryOrange = Color(0xFFFF5200);
  static const Color brandGold = Color(0xFFD4AF37);
  static const Color accentGold = Color(0xFFD4AF37); // Alias for backwards compatibility
  static const Color brandDarkGold = Color(0xFF9A7B1C);

  // Status & Utility (unchanged names)
  static const Color vegGreen = Color(0xFF0F8A65);
  static const Color successGreen = Color(0xFF0F8A65); // Alias for backwards compatibility
  static const Color nonVegRed = Color(0xFFD93B48);
  static const Color blueOffer = Color(0xFF256FEF);

  // Backgrounds & Neutrals (unchanged names)
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color bgGrey = Color(0xFFF4F5F7);
  static const Color surfaceGrey = Color(0xFFF8F9FA);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF686B78);

  // New
  static const Color borderLight = Color(0xFFEAEAEA);
  static const Color warning = Color(0xFFF5A623);
  static const Color softOrange = Color(0xFFFFF1EA);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF5200), Color(0xFFFF8A00)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD4AF37), Color(0xFFF2D46F)],
  );
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> soft = [
    BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 16, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> brand = [
    BoxShadow(color: AppColors.primaryOrange.withOpacity(.28), blurRadius: 18, offset: const Offset(0, 8)),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData get themeData {
    const scheme = ColorScheme.light(
      primary: AppColors.primaryOrange,
      onPrimary: Colors.white,
      secondary: AppColors.brandGold,
      surface: AppColors.pureWhite,
      onSurface: AppColors.textDark,
      error: AppColors.nonVegRed,
    );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.pureWhite,
      primaryColor: AppColors.primaryOrange,
      colorScheme: scheme,
      fontFamily: 'Roboto',

      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textDark),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.textDark),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textDark),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textMuted),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: .4),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark),
      ),

      cardTheme: CardThemeData(
        color: AppColors.pureWhite,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryOrange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primaryOrange.withOpacity(.35),
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: .4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryOrange,
          side: const BorderSide(color: AppColors.primaryOrange, width: 1.5),
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryOrange,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceGrey,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(AppColors.borderLight),
        enabledBorder: border(AppColors.borderLight),
        focusedBorder: border(AppColors.primaryOrange, 1.8),
        errorBorder: border(AppColors.nonVegRed),
        focusedErrorBorder: border(AppColors.nonVegRed, 1.8),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceGrey,
        selectedColor: AppColors.softOrange,
        side: const BorderSide(color: AppColors.borderLight),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.pureWhite,
        indicatorColor: AppColors.softOrange,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textDark,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.borderLight, thickness: 1),

      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}