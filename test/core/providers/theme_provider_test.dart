import 'package:buildtrack_app/core/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeController', () {
    test('defaults to system when no persisted value', () {
      final controller = ThemeController(prefsBox: null);
      expect(controller.state, ThemeMode.system);
    });

    test('setThemeMode updates state', () {
      final controller = ThemeController(prefsBox: null);
      controller.setThemeMode(ThemeMode.dark);
      expect(controller.state, ThemeMode.dark);
      controller.setThemeMode(ThemeMode.light);
      expect(controller.state, ThemeMode.light);
    });

    test('setDark toggles between light and dark', () {
      final controller = ThemeController(prefsBox: null);
      controller.setDark(true);
      expect(controller.state, ThemeMode.dark);
      controller.setDark(false);
      expect(controller.state, ThemeMode.light);
    });
  });
}
