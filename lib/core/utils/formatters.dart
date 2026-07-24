import 'package:intl/intl.dart';

class Formatters {
  static String money(
    num value, {
    String currencyCode = 'EGP',
    String locale = 'ar',
  }) {
    final formatter = NumberFormat.decimalPattern(locale)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 2;
    final formatted = _localizeNumber(formatter.format(value), locale);
    return '$formatted $currencyCode';
  }

  static String currency(
    num value, {
    String currencyCode = 'EGP',
    String locale = 'ar',
  }) {
    return NumberFormat.currency(
      locale: locale,
      symbol: currencyCode,
    ).format(value);
  }

  static String compactNumber(num value, {String locale = 'ar'}) {
    return NumberFormat.compact(locale: locale).format(value);
  }

  static String count(num value, {String locale = 'ar'}) {
    return _localizeNumber(
      NumberFormat.decimalPattern(locale).format(value),
      locale,
    );
  }

  static String date(DateTime value, {String locale = 'ar'}) {
    return DateFormat.yMMMd(locale).format(value);
  }

  /// Profit margin as a percentage of income (net ÷ totalIncome × 100),
  /// formatted for display with one decimal place (e.g. `30.7%`).
  ///
  /// Returns `null` when income is zero or negative — margin is undefined
  /// without revenue, so callers should render an em dash rather than a
  /// NaN/Infinity percentage.
  static String? profitMargin(num net, num income) {
    if (income <= 0) return null;
    final margin = net / income * 100;
    final sign = margin < 0 ? '-' : '';
    return '$sign${margin.abs().toStringAsFixed(1)}%';
  }

  static String _localizeNumber(String value, String locale) {
    final language = locale.split(RegExp('[-_]')).first.toLowerCase();
    if (language != 'ar') {
      return value;
    }

    const digits = {
      '0': '٠',
      '1': '١',
      '2': '٢',
      '3': '٣',
      '4': '٤',
      '5': '٥',
      '6': '٦',
      '7': '٧',
      '8': '٨',
      '9': '٩',
    };
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      buffer.write(
        digits[char] ??
            switch (char) {
              ',' => '٬',
              '.' => '٫',
              _ => char,
            },
      );
    }
    return buffer.toString();
  }
}
