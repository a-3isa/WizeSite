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
    final formatted = formatter.format(value);
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

  static String date(DateTime value, {String locale = 'ar'}) {
    return DateFormat.yMMMd(locale).format(value);
  }
}
