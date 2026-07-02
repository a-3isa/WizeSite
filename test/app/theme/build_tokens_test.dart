import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildTokens', () {
    test('light palette matches v2 values', () {
      expect(BuildTokens.light.income, const Color(0xFF12A150));
      expect(BuildTokens.light.expense, const Color(0xFFE5484D));
      expect(BuildTokens.light.bg, const Color(0xFFF4F5F7));
      expect(BuildTokens.light.text, const Color(0xFF141922));
    });

    test('dark palette matches v2 values', () {
      expect(BuildTokens.dark.bg, const Color(0xFF0E1116));
      expect(BuildTokens.dark.surface, const Color(0xFF171C23));
      expect(BuildTokens.dark.income, const Color(0xFF35D08A));
    });

    test('radii and spacing rhythm', () {
      expect(BuildTokens.light.rMd, 14);
      expect(BuildTokens.light.rLg, 20);
      expect(BuildTokens.light.gap, 14);
      expect(BuildTokens.light.cardPad, 18);
    });

    test('lerp at 0 returns the source token values', () {
      final lerped = BuildTokens.light.lerp(BuildTokens.dark, 0);
      expect(lerped.income, BuildTokens.light.income);
      expect(lerped.bg, BuildTokens.light.bg);
    });

    test('lerp at 1 returns the target token values', () {
      final lerped = BuildTokens.light.lerp(BuildTokens.dark, 1);
      expect(lerped.bg, BuildTokens.dark.bg);
    });
  });
}
