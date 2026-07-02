import 'package:flutter/material.dart';

/// Light-theme brand palette (Buildozer v2).
///
/// These are the *light* semantic values. Dark-mode equivalents live in
/// `BuildTokens.dark`; widgets that need to adapt should read `context.tokens`
/// rather than these constants directly.
class AppColors {
  // Brand
  static const Color constructionOrange = Color(0xFFFF6D00);
  static const Color constructionOrangeLight = Color(
    0xFFFFF1E7,
  ); // v2 accent-soft

  // Neutral/Greys
  static const Color surfaceSolid = Color(0xFFFFFFFF);
  static const Color surfaceGrey = Color(0xFFF4F5F7); // v2 app background
  static const Color borderGrey = Color(0xFFE7EAEF); // v2 hairline border
  static const Color textDark = Color(0xFF141922); // v2 heading text
  static const Color textBody = Color(0xFF67717F); // v2 muted body text

  // Semantic (v2 money colors)
  static const Color success = Color(0xFF12A150); // income / funds in
  static const Color successLight = Color(0xFFE7F6EE);
  static const Color warning = Color(0xFFF59E0B); // workers / pending
  static const Color warningLight = Color(0xFFFEF3E2);
  static const Color danger = Color(0xFFE5484D); // expense / funds out
  static const Color dangerLight = Color(0xFFFDECEC);

  // Legacy mappings for backwards compatibility during refactor
  static const Color darkGray = textDark;
  static const Color lightGray = surfaceGrey;
  static const Color white = surfaceSolid;
}
