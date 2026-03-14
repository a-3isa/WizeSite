import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all supported locales contain the full key set', () {
    final values = AppLocalizations.localizedValues;
    final enKeys = values['en']!.keys.toSet();

    for (final locale in AppLocalizations.supportedLocales) {
      final localeValues = values[locale.languageCode];
      expect(
        localeValues,
        isNotNull,
        reason: 'Missing map for locale ${locale.languageCode}',
      );
      expect(
        localeValues!.keys.toSet(),
        enKeys,
        reason: 'Locale ${locale.languageCode} does not match keyset',
      );
    }
  });
}
