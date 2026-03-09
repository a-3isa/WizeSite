import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(10));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(16));

  static ThemeData light(Locale locale) {
    final isArabic = locale.languageCode == 'ar';
    final baseFont = isArabic
        ? GoogleFonts.cairoTextTheme()
        : GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.constructionOrange,
        secondary: AppColors.darkGray,
        surface: AppColors.white,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.lightGray,
      textTheme: baseFont.copyWith(
        bodyMedium: baseFont.bodyMedium?.copyWith(color: AppColors.textDark),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(
            color: AppColors.darkGray.withValues(alpha: 0.2),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.constructionOrange,
        foregroundColor: AppColors.white,
      ),
    );
  }
}
