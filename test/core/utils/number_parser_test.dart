import 'package:buildtrack_app/core/utils/number_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NumberParser.parseDouble', () {
    test('parses plain western numbers', () {
      expect(NumberParser.parseDouble('100'), 100);
      expect(NumberParser.parseDouble('100.50'), 100.50);
    });

    test('treats grouped thousands commas as grouping', () {
      expect(NumberParser.parseDouble('1,000'), 1000);
      expect(NumberParser.parseDouble('1,000,000'), 1000000);
      expect(NumberParser.parseDouble('12,345'), 12345);
      expect(NumberParser.parseDouble('1,234.56'), 1234.56);
    });

    test('keeps comma-as-decimal for short fractions', () {
      expect(NumberParser.parseDouble('1,5'), 1.5);
      expect(NumberParser.parseDouble('12,34'), 12.34);
    });

    test('parses Arabic-Indic digits and separators', () {
      expect(NumberParser.parseDouble('١٠٠'), 100);
      expect(NumberParser.parseDouble('١٬٠٠٠'), 1000);
      expect(NumberParser.parseDouble('١٫٥'), 1.5);
    });
  });
}
