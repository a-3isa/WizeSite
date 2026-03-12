import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const Color constructionOrange = Color(
    0xFFFF6D00,
  ); // Slightly more vibrant
  static const Color constructionOrangeLight = Color(
    0xFFFFF0E6,
  ); // Light tint for cards/backgrounds

  // Neutral/Greys
  static const Color surfaceSolid = Color(0xFFFFFFFF);
  static const Color surfaceGrey = Color(
    0xFFF8FAFC,
  ); // Very light blue-grey for main background
  static const Color borderGrey = Color(0xFFE2E8F0); // Soft borders
  static const Color textDark = Color(
    0xFF0F172A,
  ); // Slate 900 for modern dark text
  static const Color textBody = Color(
    0xFF64748B,
  ); // Slate 500 for secondary text

  // Semantic
  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFEF4444); // Red 500
  static const Color dangerLight = Color(0xFFFEE2E2);

  // Legacy mappings for backwards compatibility during refactor
  static const Color darkGray = textDark;
  static const Color lightGray = surfaceGrey;
  static const Color white = surfaceSolid;
}
