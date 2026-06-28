import 'package:flutter/services.dart';

/// Groups the integer part of a numeric text field with thousands separators
/// (commas) as the user types, e.g. `1000000` -> `1,000,000`.
///
/// Uses `.` as the decimal separator and limits the fraction to
/// [decimalDigits]. Pair with [NumberParser], which strips grouping commas
/// before parsing. The cursor is placed at the end after each edit, which is
/// the expected behaviour for amount entry.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter({this.decimalDigits = 2});

  final int decimalDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) {
      return newValue;
    }

    // Integer fields drop the decimal point entirely.
    if (decimalDigits <= 0) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        return const TextEditingValue(text: '');
      }
      final groupedInt = _group(digits);
      return TextEditingValue(
        text: groupedInt,
        selection: TextSelection.collapsed(offset: groupedInt.length),
      );
    }

    // Keep digits and dots only; the grouping commas are recomputed here.
    var cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final firstDot = cleaned.indexOf('.');
    String intDigits;
    String? decDigits;
    if (firstDot == -1) {
      intDigits = cleaned;
    } else {
      intDigits = cleaned.substring(0, firstDot);
      // Drop any extra dots and clamp the fraction length.
      decDigits = cleaned.substring(firstDot + 1).replaceAll('.', '');
      if (decDigits.length > decimalDigits) {
        decDigits = decDigits.substring(0, decimalDigits);
      }
    }

    final grouped = _group(intDigits);

    final String result;
    if (firstDot == -1) {
      result = grouped;
    } else {
      result = '$grouped.${decDigits ?? ''}';
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }

  /// Inserts a comma every three digits from the right. Works on the raw digit
  /// string to avoid integer-overflow on very large inputs.
  static String _group(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    final buffer = StringBuffer();
    final length = digits.length;
    for (var i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Formats an already-known numeric string for display in a controller so the
  /// initial value matches the live-typed grouping (e.g. `1000.00` ->
  /// `1,000.00`).
  static String formatInitial(String value, {int decimalDigits = 2}) {
    return ThousandsSeparatorInputFormatter(decimalDigits: decimalDigits)
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: value))
        .text;
  }
}
