/// Sum of expense item amounts (feature 005), added in whole piastres so the
/// total equals the server's exact NUMERIC sum (no floating-point drift).
double expenseItemsTotal(Iterable<Map<String, dynamic>> items) {
  var piastres = 0;
  for (final item in items) {
    final amount = item['amount'];
    final value = amount is num
        ? amount.toDouble()
        : double.tryParse('${amount ?? ''}') ?? 0;
    piastres += (value * 100).round();
  }
  return piastres / 100;
}
