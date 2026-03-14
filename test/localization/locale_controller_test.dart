import 'dart:io';

import 'package:buildtrack_app/app/localization/locale_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('LocaleController persists and restores the selected locale', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'wizesite_locale_test_',
    );
    Hive.init(tempDir.path);

    final box = await Hive.openBox<String>(LocaleController.prefsBoxName);

    final controller = LocaleController(
      prefsBox: box,
      deviceLocale: const Locale('en'),
    );
    expect(controller.state, const Locale('en'));

    controller.setLocale(const Locale('ar'));
    expect(box.get(LocaleController.localeCodeKey), 'ar');

    final restoredController = LocaleController(
      prefsBox: box,
      deviceLocale: const Locale('en'),
    );
    expect(restoredController.state, const Locale('ar'));

    await box.close();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });
}
