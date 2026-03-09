import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(const Locale('ar'));

  void setLocale(Locale locale) {
    state = locale;
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>(
      (ref) => LocaleController(),
    );
