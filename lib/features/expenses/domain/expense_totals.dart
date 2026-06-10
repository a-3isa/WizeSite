import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';

/// Pure aggregation helpers shared by the expenses screen and the PDF
/// exporter so on-screen totals and exported totals are guaranteed to match.

double sumExpenseAmounts(Iterable<Expense> expenses) =>
    expenses.fold<double>(0, (sum, item) => sum + item.amount);

double sumPaymentAmounts(Iterable<PaymentRecord> payments) =>
    payments.fold<double>(0, (sum, item) => sum + item.amount);

Map<String, double> expenseCategoryTotals(Iterable<Expense> expenses) {
  final totals = <String, double>{};
  for (final item in expenses) {
    totals.update(
      item.category,
      (value) => value + item.amount,
      ifAbsent: () => item.amount,
    );
  }
  return totals;
}

Map<String, double> expensePaymentMethodTotals(Iterable<Expense> expenses) {
  final totals = <String, double>{};
  for (final item in expenses) {
    final method = item.paymentMethod.isEmpty ? 'other' : item.paymentMethod;
    totals.update(
      method,
      (value) => value + item.amount,
      ifAbsent: () => item.amount,
    );
  }
  return totals;
}

Map<String, double> paymentMethodTotals(Iterable<PaymentRecord> payments) {
  final totals = <String, double>{};
  for (final item in payments) {
    final method = item.paymentMethod.isEmpty ? 'other' : item.paymentMethod;
    totals.update(
      method,
      (value) => value + item.amount,
      ifAbsent: () => item.amount,
    );
  }
  return totals;
}

/// One day's worth of expenses, used for the "daily breakdown" report section.
class DailyTotal {
  const DailyTotal({
    required this.day,
    required this.count,
    required this.total,
  });

  final DateTime day; // date-only (midnight)
  final int count;
  final double total;
}

/// Groups expenses by calendar day, newest day first.
List<DailyTotal> dailyExpenseBreakdown(Iterable<Expense> expenses) {
  final byDay = <DateTime, DailyTotal>{};
  for (final item in expenses) {
    final day = DateTime(item.date.year, item.date.month, item.date.day);
    final existing = byDay[day];
    byDay[day] = existing == null
        ? DailyTotal(day: day, count: 1, total: item.amount)
        : DailyTotal(
            day: day,
            count: existing.count + 1,
            total: existing.total + item.amount,
          );
  }
  final rows = byDay.values.toList();
  rows.sort((a, b) => b.day.compareTo(a.day));
  return rows;
}

/// Inclusive day-boundary range check shared by screens, filters, and exports.
bool isWithinRange(DateTime date, DateTime? start, DateTime? end) {
  if (start != null) {
    final dayStart = DateTime(start.year, start.month, start.day);
    if (date.isBefore(dayStart)) {
      return false;
    }
  }
  if (end != null) {
    final dayEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    if (date.isAfter(dayEnd)) {
      return false;
    }
  }
  return true;
}
