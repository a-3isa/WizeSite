import 'package:intl/intl.dart';

class Formatters {
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

  static String date(DateTime value, {String locale = 'ar'}) {
    return DateFormat.yMMMd(locale).format(value);
  }
}
