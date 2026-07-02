import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';

/// Controls the app-wide [ThemeMode], persisted in the shared `app_prefs` Hive
/// box (same box used by `LocaleController`). Defaults to [ThemeMode.system].
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController({Box<String>? prefsBox})
    : _prefsBox = prefsBox ?? _tryOpenPrefsBox(),
      super(ThemeMode.system) {
    state = _resolveInitial();
  }

  static const String prefsBoxName = 'app_prefs';
  static const String themeModeKey = 'theme_mode';

  final Box<String>? _prefsBox;

  static Box<String>? _tryOpenPrefsBox() {
    if (!Hive.isBoxOpen(prefsBoxName)) {
      return null;
    }
    return Hive.box<String>(prefsBoxName);
  }

  ThemeMode _resolveInitial() {
    final saved = _prefsBox?.get(themeModeKey);
    return _decode(saved) ?? ThemeMode.system;
  }

  static ThemeMode? _decode(String? code) {
    switch (code) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _prefsBox?.put(themeModeKey, _encode(mode));
  }

  /// Convenience toggle between light and dark (used by the More screen switch).
  void setDark(bool dark) =>
      setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>(
      (ref) => ThemeController(),
    );
