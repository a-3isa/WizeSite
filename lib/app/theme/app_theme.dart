import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(28));

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: AppColors.textDark.withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static ThemeData light(Locale locale) {
    final isArabic = locale.languageCode == 'ar';
    final baseFont = isArabic
        ? GoogleFonts.cairoTextTheme()
        : GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.constructionOrange,
        secondary: AppColors.textBody,
        surface: AppColors.surfaceGrey, // Main background
        surfaceContainer: AppColors.surfaceSolid, // Cards usually sit on this
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.surfaceGrey,
      textTheme: baseFont.copyWith(
        displayLarge: baseFont.displayLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        displayMedium: baseFont.displayMedium?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: baseFont.titleLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseFont.titleMedium?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseFont.bodyLarge?.copyWith(
          color: AppColors.textBody,
          height: 1.5,
        ),
        bodyMedium: baseFont.bodyMedium?.copyWith(
          color: AppColors.textBody,
          height: 1.5,
        ),
        labelLarge: baseFont.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ), // Buttons
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceGrey,
        foregroundColor: AppColors.textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: baseFont.titleLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceSolid,
        shadowColor: AppColors.textDark.withValues(alpha: 0.05),
        elevation: 4, // Utilizing Material 3 soft shadows
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceSolid,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: AppColors.borderGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: AppColors.borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(
            color: AppColors.constructionOrange,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        hintStyle: baseFont.bodyMedium?.copyWith(color: AppColors.borderGrey),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: baseFont.bodyLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceSolid),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          prefixIconColor: AppColors.constructionOrange,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceSolid),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.constructionOrange,
          foregroundColor: AppColors.surfaceSolid,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.borderGrey),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.constructionOrange,
        foregroundColor: AppColors.surfaceSolid,
        shape: RoundedRectangleBorder(borderRadius: radiusXl),
        elevation: 4,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceSolid,
        elevation: 10,
        shadowColor: AppColors.textDark.withValues(alpha: 0.1),
        indicatorColor: AppColors.constructionOrangeLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return baseFont.labelSmall?.copyWith(
              color: AppColors.constructionOrange,
              fontWeight: FontWeight.bold,
            );
          }
          return baseFont.labelSmall?.copyWith(color: AppColors.textBody);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.constructionOrange);
          }
          return const IconThemeData(color: AppColors.textBody);
        }),
      ),
    );
  }
}
