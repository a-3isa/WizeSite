import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/utils/expense_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy labor voice parses as worker', () {
    expect(normalizeExpenseCategory('labor'), AccountingCategories.worker);
  });

  test('worker stays worker', () {
    expect(normalizeExpenseCategory('worker'), AccountingCategories.worker);
  });

  test('unknown categories fall back to other', () {
    expect(normalizeExpenseCategory('mystery'), AccountingCategories.other);
    expect(normalizeExpenseCategory(null), AccountingCategories.other);
  });
}
