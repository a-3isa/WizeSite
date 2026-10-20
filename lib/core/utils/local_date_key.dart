/// The device's calendar day as `YYYY-MM-DD`, sent to the AI so relative
/// dates ("امبارح", "yesterday") resolve against the user's own day.
String localDateKey(DateTime now) {
  final local = now.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
