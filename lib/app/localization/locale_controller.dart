import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

class LocaleController extends StateNotifier<Locale> {
  LocaleController({Box<String>? prefsBox, Locale? deviceLocale})
    : _prefsBox = prefsBox ?? _tryOpenPrefsBox(),
      _deviceLocale =
          deviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
      super(const Locale('ar')) {
    state = _resolveInitialLocale();
  }

  static const String prefsBoxName = 'app_prefs';
  static const String localeCodeKey = 'locale_code';

  final Box<String>? _prefsBox;
  final Locale _deviceLocale;

  static Box<String>? _tryOpenPrefsBox() {
    if (!Hive.isBoxOpen(prefsBoxName)) {
      return null;
    }
    return Hive.box<String>(prefsBoxName);
  }

  Locale _resolveInitialLocale() {
    final savedCode = _prefsBox?.get(localeCodeKey);
    if (savedCode != null && savedCode.isNotEmpty) {
      final savedLocale = _supportedLocale(savedCode);
      if (savedLocale != null) {
        return savedLocale;
      }
    }

    final deviceLocale = _supportedLocale(_deviceLocale.languageCode);
    if (deviceLocale != null) {
      return deviceLocale;
    }

    return const Locale('ar');
  }

  Locale? _supportedLocale(String languageCode) {
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == languageCode) {
        return locale;
      }
    }
    return null;
  }

  void setLocale(Locale locale) {
    final normalized = _supportedLocale(locale.languageCode);
    if (normalized == null) {
      return;
    }
    state = normalized;
    _prefsBox?.put(localeCodeKey, normalized.languageCode);
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>(
      (ref) => LocaleController(),
    );
