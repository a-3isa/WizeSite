import 'package:buildtrack_app/core/constants/accounting_categories.dart';

/// Maps deprecated `labor` onto the selectable `worker` category.
String normalizeExpenseCategory(String? category) {
  final raw = (category ?? '').trim().toLowerCase();
  if (raw == AccountingCategories.labor) {
    return AccountingCategories.worker;
  }
  if (AccountingCategories.values.contains(raw)) {
    return raw;
  }
  return AccountingCategories.other;
}
