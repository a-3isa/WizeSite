/// Parses numeric strings that may contain Arabic-Indic (٠-٩), Eastern
/// Arabic-Indic/Persian (۰-۹), or Western Arabic (0-9) digits.
/// Also handles the Arabic decimal separator '٫' and strips the Arabic
/// thousands separator '٬'.
abstract final class NumberParser {
  static String normalize(String text) {
    return text
        .trim()
        // Arabic-Indic digits U+0660–U+0669
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        // Eastern Arabic-Indic / Persian digits U+06F0–U+06F9
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9')
        // Arabic decimal separator → period
        .replaceAll('٫', '.')
        // Arabic thousands separator → remove
        .replaceAll('٬', '')
        // Regular comma used as decimal in some locales → period
        .replaceAll(',', '.');
  }

  static double? parseDouble(String text) => double.tryParse(normalize(text));

  static int? parseInt(String text) => int.tryParse(normalize(text));
}
