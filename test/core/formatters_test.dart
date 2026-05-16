import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters.money', () {
    test(
      'formats whole money values consistently with grouping and currency',
      () {
        expect(
          Formatters.money(1234567, currencyCode: 'EGP', locale: 'en'),
          '1,234,567 EGP',
        );
      },
    );

    test('keeps useful decimals without trailing zero noise', () {
      expect(
        Formatters.money(1234.5, currencyCode: 'EGP', locale: 'en'),
        '1,234.5 EGP',
      );
      expect(
        Formatters.money(1234.567, currencyCode: 'EGP', locale: 'en'),
        '1,234.57 EGP',
      );
    });
  });
}
