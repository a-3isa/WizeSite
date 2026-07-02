import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Design tokens for the Buildozer v2 design system.
///
/// Exposes every semantic color, shadow, spacing and radius value from the
/// design-system `theme.css`. Registered on [ThemeData.extensions] for both the
/// light and dark themes, so widgets can read dark-aware tokens via
/// `Theme.of(context).extension<BuildTokens>()` (or `context.tokens`).
@immutable
class BuildTokens extends ThemeExtension<BuildTokens> {
  const BuildTokens({
    required this.accent,
    required this.accentPress,
    required this.accentSoft,
    required this.onAccent,
    required this.income,
    required this.incomeSoft,
    required this.expense,
    required this.expenseSoft,
    required this.warning,
    required this.warningSoft,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.scrim,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowNav,
    required this.gap,
    required this.cardPad,
    required this.sectionGap,
    required this.rSm,
    required this.rMd,
    required this.rLg,
    required this.rXl,
  });

  final Color accent;
  final Color accentPress;
  final Color accentSoft;
  final Color onAccent;

  final Color income;
  final Color incomeSoft;
  final Color expense;
  final Color expenseSoft;
  final Color warning;
  final Color warningSoft;

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderStrong;

  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color scrim;

  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowNav;

  final double gap;
  final double cardPad;
  final double sectionGap;

  final double rSm;
  final double rMd;
  final double rLg;
  final double rXl;

  static const double pill = 999;

  BorderRadius get radiusSm => BorderRadius.circular(rSm);
  BorderRadius get radiusMd => BorderRadius.circular(rMd);
  BorderRadius get radiusLg => BorderRadius.circular(rLg);
  BorderRadius get radiusXl => BorderRadius.circular(rXl);
  BorderRadius get radiusPill => BorderRadius.circular(pill);

  // ---- Light (default) ----
  static const BuildTokens light = BuildTokens(
    accent: Color(0xFFFF6D00),
    accentPress: Color(0xFFE76100),
    accentSoft: Color(0xFFFFF1E7),
    onAccent: Color(0xFFFFFFFF),
    income: Color(0xFF12A150),
    incomeSoft: Color(0xFFE7F6EE),
    expense: Color(0xFFE5484D),
    expenseSoft: Color(0xFFFDECEC),
    warning: Color(0xFFF59E0B),
    warningSoft: Color(0xFFFEF3E2),
    bg: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F3F6),
    surface3: Color(0xFFE9ECF1),
    border: Color(0xFFE7EAEF),
    borderStrong: Color(0xFFD7DCE3),
    text: Color(0xFF141922),
    textMuted: Color(0xFF67717F),
    textFaint: Color(0xFF99A2AE),
    scrim: Color(0x6B141922), // rgba(20,25,34,.42)
    shadowSm: _lightShadowSm,
    shadowMd: _lightShadowMd,
    shadowNav: _lightShadowNav,
    gap: 14,
    cardPad: 18,
    sectionGap: 22,
    rSm: 10,
    rMd: 14,
    rLg: 20,
    rXl: 26,
  );

  // ---- Dark ----
  static const BuildTokens dark = BuildTokens(
    accent: Color(0xFFFF7D1F),
    accentPress: Color(0xFFFF6D00),
    accentSoft: Color(0x29FF7D1F), // rgba(255,125,31,.16)
    onAccent: Color(0xFF16130F),
    income: Color(0xFF35D08A),
    incomeSoft: Color(0x2635D08A), // rgba(53,208,138,.15)
    expense: Color(0xFFFF6B6B),
    expenseSoft: Color(0x26FF6B6B),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0x26FBBF24),
    bg: Color(0xFF0E1116),
    surface: Color(0xFF171C23),
    surface2: Color(0xFF1E242D),
    surface3: Color(0xFF262D38),
    border: Color(0xFF262D38),
    borderStrong: Color(0xFF333C49),
    text: Color(0xFFEDF0F4),
    textMuted: Color(0xFF949FAD),
    textFaint: Color(0xFF6A7482),
    scrim: Color(0x99000000), // rgba(0,0,0,.6)
    shadowSm: _darkShadowSm,
    shadowMd: _darkShadowMd,
    shadowNav: _darkShadowNav,
    gap: 14,
    cardPad: 18,
    sectionGap: 22,
    rSm: 10,
    rMd: 14,
    rLg: 20,
    rXl: 26,
  );

  static const List<BoxShadow> _lightShadowSm = [
    BoxShadow(color: Color(0x0D141922), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A141922), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> _lightShadowMd = [
    BoxShadow(color: Color(0x12141922), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0D141922), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const List<BoxShadow> _lightShadowNav = [
    BoxShadow(color: Color(0x0F141922), blurRadius: 20, offset: Offset(0, -4)),
  ];

  static const List<BoxShadow> _darkShadowSm = [
    BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> _darkShadowMd = [
    BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> _darkShadowNav = [
    BoxShadow(color: Color(0x73000000), blurRadius: 22, offset: Offset(0, -4)),
  ];

  @override
  BuildTokens copyWith({
    Color? accent,
    Color? accentPress,
    Color? accentSoft,
    Color? onAccent,
    Color? income,
    Color? incomeSoft,
    Color? expense,
    Color? expenseSoft,
    Color? warning,
    Color? warningSoft,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? scrim,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowNav,
    double? gap,
    double? cardPad,
    double? sectionGap,
    double? rSm,
    double? rMd,
    double? rLg,
    double? rXl,
  }) {
    return BuildTokens(
      accent: accent ?? this.accent,
      accentPress: accentPress ?? this.accentPress,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      income: income ?? this.income,
      incomeSoft: incomeSoft ?? this.incomeSoft,
      expense: expense ?? this.expense,
      expenseSoft: expenseSoft ?? this.expenseSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      scrim: scrim ?? this.scrim,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowNav: shadowNav ?? this.shadowNav,
      gap: gap ?? this.gap,
      cardPad: cardPad ?? this.cardPad,
      sectionGap: sectionGap ?? this.sectionGap,
      rSm: rSm ?? this.rSm,
      rMd: rMd ?? this.rMd,
      rLg: rLg ?? this.rLg,
      rXl: rXl ?? this.rXl,
    );
  }

  @override
  BuildTokens lerp(ThemeExtension<BuildTokens>? other, double t) {
    if (other is! BuildTokens) return this;
    return BuildTokens(
      accent: Color.lerp(accent, other.accent, t)!,
      accentPress: Color.lerp(accentPress, other.accentPress, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      income: Color.lerp(income, other.income, t)!,
      incomeSoft: Color.lerp(incomeSoft, other.incomeSoft, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseSoft: Color.lerp(expenseSoft, other.expenseSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadowSm: t < 0.5 ? shadowSm : other.shadowSm,
      shadowMd: t < 0.5 ? shadowMd : other.shadowMd,
      shadowNav: t < 0.5 ? shadowNav : other.shadowNav,
      gap: lerpDouble(gap, other.gap, t)!,
      cardPad: lerpDouble(cardPad, other.cardPad, t)!,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t)!,
      rSm: lerpDouble(rSm, other.rSm, t)!,
      rMd: lerpDouble(rMd, other.rMd, t)!,
      rLg: lerpDouble(rLg, other.rLg, t)!,
      rXl: lerpDouble(rXl, other.rXl, t)!,
    );
  }
}

/// Convenience access: `context.tokens`.
extension BuildTokensX on BuildContext {
  BuildTokens get tokens =>
      Theme.of(this).extension<BuildTokens>() ?? BuildTokens.light;
}
