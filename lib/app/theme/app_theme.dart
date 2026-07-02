import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(10));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(14));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusXl = BorderRadius.all(Radius.circular(26));

  static List<BoxShadow> get softShadow => BuildTokens.light.shadowMd;

  static ThemeData light(Locale locale) => _build(
    locale: locale,
    tokens: BuildTokens.light,
    brightness: Brightness.light,
  );

  static ThemeData dark(Locale locale) => _build(
    locale: locale,
    tokens: BuildTokens.dark,
    brightness: Brightness.dark,
  );

  static ThemeData _build({
    required Locale locale,
    required BuildTokens tokens,
    required Brightness brightness,
  }) {
    final isArabic = locale.languageCode == 'ar';
    final baseFont = isArabic
        ? GoogleFonts.cairoTextTheme(
            brightness == Brightness.dark ? ThemeData.dark().textTheme : null,
          )
        : GoogleFonts.interTextTheme(
            brightness == Brightness.dark ? ThemeData.dark().textTheme : null,
          );

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: tokens.onAccent,
      secondary: tokens.textMuted,
      onSecondary: tokens.onAccent,
      surface: tokens.surface,
      onSurface: tokens.text,
      error: tokens.expense,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme.copyWith(
        surfaceContainer: tokens.surface,
        surfaceContainerHighest: tokens.surface2,
        outline: tokens.border,
        outlineVariant: tokens.border,
      ),
      extensions: [tokens],
      scaffoldBackgroundColor: tokens.bg,
      textTheme: baseFont.copyWith(
        displayLarge: baseFont.displayLarge?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        displayMedium: baseFont.displayMedium?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: baseFont.headlineMedium?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: baseFont.titleLarge?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseFont.titleMedium?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseFont.bodyLarge?.copyWith(
          color: tokens.textMuted,
          height: 1.5,
        ),
        bodyMedium: baseFont.bodyMedium?.copyWith(
          color: tokens.textMuted,
          height: 1.5,
        ),
        labelLarge: baseFont.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bg,
        foregroundColor: tokens.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: baseFont.titleLarge?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        shadowColor: tokens.text.withValues(alpha: 0.05),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: tokens.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: tokens.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: tokens.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: tokens.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: tokens.expense),
        ),
        hintStyle: baseFont.bodyMedium?.copyWith(color: tokens.textFaint),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: baseFont.bodyLarge?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w600,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(tokens.surface),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          prefixIconColor: tokens.accent,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(tokens.surface),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: tokens.onAccent,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.text,
          minimumSize: const Size.fromHeight(56),
          side: BorderSide(color: tokens.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: tokens.accent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        shape: RoundedRectangleBorder(borderRadius: radiusXl),
        elevation: 4,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface,
        elevation: 10,
        shadowColor: tokens.text.withValues(alpha: 0.1),
        indicatorColor: tokens.accentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return baseFont.labelSmall?.copyWith(
              color: tokens.accent,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            );
          }
          return baseFont.labelSmall?.copyWith(
            color: tokens.textMuted,
            decoration: TextDecoration.none,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: tokens.accent);
          }
          return IconThemeData(color: tokens.textMuted);
        }),
      ),
    );
  }
}
