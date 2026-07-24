import 'package:flutter/material.dart';

/// Animates a big/prominent, already-formatted numeric string from zero (or
/// its previous rendered value) up to its final value over [duration],
/// instead of the figure popping straight in fully-formed (the "number
/// counting animation" called out by the v2 UI audit's Interaction
/// Improvements section).
///
/// [value] must already be fully formatted by the caller exactly as it
/// should appear at rest -- sign, thousands separators, decimal places,
/// locale digit shapes (this app defaults to Arabic and supports
/// Arabic-Indic digits/separators produced by [Formatters], e.g. `Formatters
/// .money`), and any trailing unit/currency suffix. This widget only
/// computes what to render on the frames *before* that rest state; the
/// settled frame always renders [value] verbatim, so callers get a
/// pixel-identical result to not animating at all once the animation
/// completes.
///
/// Strings with no parseable digits (e.g. an em dash placeholder for "no
/// data") are rendered as-is, unanimated.
///
/// Respects reduced-motion: when `MediaQuery.of(context).disableAnimations`
/// is true, the target value is shown immediately with no animation.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter(
    this.value, {
    this.duration = const Duration(milliseconds: 500),
    this.curve = Curves.easeOutCubic,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    super.key,
  });

  /// The fully-formatted target string, e.g. `"84,500"`, `"−45,000"`,
  /// `"38.4%"`, or an Arabic-localized `"١٬٢٣٤٫٥٠ EGP"`.
  final String value;
  final Duration duration;
  final Curve curve;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final parsed = _ParsedNumber.parse(value);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (parsed == null || reduceMotion) {
      return _text(value);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: parsed.magnitude),
      duration: duration,
      curve: curve,
      builder: (context, animated, child) {
        // Guarantee a pixel-identical rest state: once the tween has reached
        // its target exactly (always true on the final frame -- Tween.lerp
        // at t=1.0 returns `end` exactly), fall back to the caller's own
        // verbatim string rather than our re-composed approximation.
        final settled = animated == parsed.magnitude;
        return _text(settled ? value : parsed.format(animated));
      },
    );
  }

  Widget _text(String text) => Text(
    text,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

const _kWesternDigits = '0123456789';
const _kArabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

bool _isDigit(String ch) =>
    _kWesternDigits.contains(ch) || _kArabicIndicDigits.contains(ch);

int _digitValue(String ch) {
  final western = _kWesternDigits.indexOf(ch);
  if (western != -1) return western;
  return _kArabicIndicDigits.indexOf(ch);
}

/// Parses an already-formatted numeric string into its constituent parts
/// (sign, magnitude, decimal precision, digit family, grouping/decimal
/// separators, and any literal prefix/suffix) so intermediate animation
/// frames can be re-composed in the same visual shape as the final string.
class _ParsedNumber {
  const _ParsedNumber({
    required this.prefix,
    required this.negative,
    required this.magnitude,
    required this.decimalDigits,
    required this.useArabicIndicDigits,
    required this.groupSeparator,
    required this.decimalSeparator,
    required this.suffix,
  });

  final String prefix;
  final bool negative;
  final double magnitude;
  final int decimalDigits;
  final bool useArabicIndicDigits;
  final String groupSeparator;
  final String decimalSeparator;
  final String suffix;

  static _ParsedNumber? parse(String input) {
    var firstDigit = -1;
    for (var i = 0; i < input.length; i++) {
      if (_isDigit(input[i])) {
        firstDigit = i;
        break;
      }
    }
    if (firstDigit == -1) return null;

    var prefixEnd = firstDigit;
    var negative = false;
    if (prefixEnd > 0) {
      final maybeSign = input[prefixEnd - 1];
      if (maybeSign == '-' || maybeSign == '−') {
        negative = true;
        prefixEnd -= 1;
      }
    }
    final prefix = input.substring(0, prefixEnd);

    var lastDigit = firstDigit;
    for (var i = input.length - 1; i >= firstDigit; i--) {
      if (_isDigit(input[i])) {
        lastDigit = i;
        break;
      }
    }
    final suffix = input.substring(lastDigit + 1);
    final numeralPart = input.substring(firstDigit, lastDigit + 1);

    final useArabicIndicDigits = numeralPart.runes.any(
      (r) => _kArabicIndicDigits.contains(String.fromCharCode(r)),
    );
    final groupSeparator = numeralPart.contains('٬') ? '٬' : ',';
    final decimalSeparator = numeralPart.contains('٫') ? '٫' : '.';

    final canonical = StringBuffer();
    var decimalDigits = 0;
    var afterDecimal = false;
    for (var i = 0; i < numeralPart.length; i++) {
      final ch = numeralPart[i];
      if (_isDigit(ch)) {
        canonical.write(_digitValue(ch));
        if (afterDecimal) decimalDigits++;
      } else if (ch == decimalSeparator) {
        canonical.write('.');
        afterDecimal = true;
      }
      // Group separators are dropped -- they carry no numeric value.
    }
    final magnitude = double.tryParse(canonical.toString());
    if (magnitude == null) return null;

    return _ParsedNumber(
      prefix: prefix,
      negative: negative,
      magnitude: magnitude,
      decimalDigits: decimalDigits,
      useArabicIndicDigits: useArabicIndicDigits,
      groupSeparator: groupSeparator,
      decimalSeparator: decimalSeparator,
      suffix: suffix,
    );
  }

  String format(double animatedMagnitude) {
    final safe = animatedMagnitude < 0 ? 0.0 : animatedMagnitude;
    final fixed = safe.toStringAsFixed(decimalDigits);
    final parts = fixed.split('.');
    final grouped = _group(parts[0]);
    var numeral = decimalDigits > 0
        ? '$grouped$decimalSeparator${parts[1]}'
        : grouped;
    if (useArabicIndicDigits) {
      final buffer = StringBuffer();
      for (var i = 0; i < numeral.length; i++) {
        final ch = numeral[i];
        final western = _kWesternDigits.indexOf(ch);
        buffer.write(western == -1 ? ch : _kArabicIndicDigits[western]);
      }
      numeral = buffer.toString();
    }
    final sign = negative && safe > 0 ? '−' : '';
    return '$prefix$sign$numeral$suffix';
  }

  String _group(String integerDigits) {
    final buffer = StringBuffer();
    final len = integerDigits.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write(groupSeparator);
      buffer.write(integerDigits[i]);
    }
    return buffer.toString();
  }
}
