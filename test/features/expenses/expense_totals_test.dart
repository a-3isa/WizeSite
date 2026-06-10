import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_totals.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _expense({
  required double amount,
  required String category,
  required String paymentMethod,
  String date = '2026-01-01T00:00:00.000',
}) {
  return Expense.fromMap('e', {
    'amount': amount,
    'category': category,
    'paymentMethod': paymentMethod,
    'date': date,
  });
}

PaymentRecord _payment({
  required double amount,
  required String paymentMethod,
}) {
  return PaymentRecord.fromMap('p', {
    'amount': amount,
    'paymentMethod': paymentMethod,
    'date': '2026-01-01T00:00:00.000',
  });
}

void main() {
  group('expense totals', () {
    final expenses = [
      _expense(amount: 100, category: 'materials', paymentMethod: 'cash'),
      _expense(amount: 250, category: 'materials', paymentMethod: 'bank'),
      _expense(amount: 50, category: 'transport', paymentMethod: 'cash'),
      _expense(amount: 75, category: 'transport', paymentMethod: ''),
    ];

    test('sum matches the arithmetic total', () {
      expect(sumExpenseAmounts(expenses), 475);
    });

    test('category totals group correctly', () {
      final totals = expenseCategoryTotals(expenses);
      expect(totals['materials'], 350);
      expect(totals['transport'], 125);
      // Sum of category totals equals the grand total shown on screen / in PDF.
      final sumOfCategories = totals.values.fold<double>(0, (a, b) => a + b);
      expect(sumOfCategories, sumExpenseAmounts(expenses));
    });

    test('empty payment method is bucketed as "other"', () {
      final totals = expensePaymentMethodTotals(expenses);
      expect(totals['cash'], 150);
      expect(totals['bank'], 250);
      expect(totals['other'], 75);
    });
  });

  group('payment totals', () {
    final payments = [
      _payment(amount: 200, paymentMethod: 'cash'),
      _payment(amount: 300, paymentMethod: 'bank'),
      _payment(amount: 100, paymentMethod: ''),
    ];

    test('sum matches the arithmetic total', () {
      expect(sumPaymentAmounts(payments), 600);
    });

    test('method totals bucket empty as "other" and sum to grand total', () {
      final totals = paymentMethodTotals(payments);
      expect(totals['cash'], 200);
      expect(totals['bank'], 300);
      expect(totals['other'], 100);
      final sumOfMethods = totals.values.fold<double>(0, (a, b) => a + b);
      expect(sumOfMethods, sumPaymentAmounts(payments));
    });
  });

  group('daily breakdown', () {
    final expenses = [
      _expense(
        amount: 100,
        category: 'materials',
        paymentMethod: 'cash',
        date: '2026-05-24T09:00:00.000',
      ),
      _expense(
        amount: 200,
        category: 'materials',
        paymentMethod: 'cash',
        date: '2026-05-24T18:00:00.000',
      ),
      _expense(
        amount: 50,
        category: 'transport',
        paymentMethod: 'cash',
        date: '2026-05-23T12:00:00.000',
      ),
    ];

    test('groups by calendar day, newest first, with counts and totals', () {
      final rows = dailyExpenseBreakdown(expenses);
      expect(rows.length, 2);
      // Newest day first.
      expect(rows.first.day, DateTime(2026, 5, 24));
      expect(rows.first.count, 2);
      expect(rows.first.total, 300);
      expect(rows.last.day, DateTime(2026, 5, 23));
      expect(rows.last.count, 1);
      expect(rows.last.total, 50);
      // Daily totals reconcile with the grand total.
      final sumOfDays = rows.fold<double>(0, (a, b) => a + b.total);
      expect(sumOfDays, sumExpenseAmounts(expenses));
    });
  });

  group('isWithinRange', () {
    final date = DateTime(2026, 5, 24, 14, 30);

    test('null bounds always match', () {
      expect(isWithinRange(date, null, null), isTrue);
    });

    test('end bound is inclusive of the whole day', () {
      expect(isWithinRange(date, null, DateTime(2026, 5, 24)), isTrue);
    });

    test('before start is excluded', () {
      expect(isWithinRange(date, DateTime(2026, 5, 25), null), isFalse);
    });

    test('after end is excluded', () {
      expect(isWithinRange(date, null, DateTime(2026, 5, 23)), isFalse);
    });
  });
}
