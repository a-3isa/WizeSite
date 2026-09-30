import 'package:buildtrack_app/features/expenses/domain/expense.dart';

enum ExpenseGroupMode {
  list,
  date,
  relativeDate,
  category,
  entity,
  paymentMethod,
}

class ExpenseGroup {
  const ExpenseGroup({
    required this.id,
    required this.title,
    required this.totalAmount,
    required this.transactionCount,
    required this.items,
  });

  final String id;
  final String title;
  final double totalAmount;
  final int transactionCount;
  final List<Expense> items;
}

List<ExpenseGroup> groupExpenses(
  List<Expense> expenses,
  ExpenseGroupMode mode, {
  DateTime? now,
}) {
  if (mode == ExpenseGroupMode.list) {
    return [
      ExpenseGroup(
        id: 'list',
        title: 'allExpenses',
        totalAmount: _sum(expenses),
        transactionCount: expenses.length,
        items: _sorted(expenses),
      ),
    ];
  }

  final groups = <String, List<Expense>>{};
  final titles = <String, String>{};
  for (final expense in _sorted(expenses)) {
    final key = _groupKey(expense, mode, now: now);
    groups.putIfAbsent(key.id, () => <Expense>[]).add(expense);
    titles[key.id] = key.title;
  }

  return groups.entries
      .map(
        (entry) => ExpenseGroup(
          id: entry.key,
          title: titles[entry.key] ?? entry.key,
          totalAmount: _sum(entry.value),
          transactionCount: entry.value.length,
          items: List<Expense>.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
}

({String id, String title}) _groupKey(
  Expense expense,
  ExpenseGroupMode mode, {
  DateTime? now,
}) {
  switch (mode) {
    case ExpenseGroupMode.date:
      final id = _dateId(expense.date);
      return (id: id, title: id);
    case ExpenseGroupMode.relativeDate:
      return _relativeDateKey(expense.date, now ?? DateTime.now());
    case ExpenseGroupMode.category:
      final category = _fallback(expense.category, 'unassigned');
      return (id: category, title: category);
    case ExpenseGroupMode.entity:
      final entity = _fallback(
        expense.entityName.isNotEmpty
            ? expense.entityName
            : expense.supplierName,
        'unassigned',
      );
      return (id: entity, title: entity);
    case ExpenseGroupMode.paymentMethod:
      final method = _fallback(expense.paymentMethod, 'unassigned');
      return (id: method, title: method);
    case ExpenseGroupMode.list:
      return (id: 'list', title: 'allExpenses');
  }
}

({String id, String title}) _relativeDateKey(DateTime date, DateTime now) {
  final normalizedDate = DateTime.utc(date.year, date.month, date.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  if (normalizedDate == today) {
    return (id: 'today', title: 'today');
  }
  if (normalizedDate == today.subtract(const Duration(days: 1))) {
    return (id: 'yesterday', title: 'yesterday');
  }
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!normalizedDate.isBefore(weekStart) && !normalizedDate.isAfter(today)) {
    return (id: 'current_week', title: 'thisWeek');
  }
  if (normalizedDate.year == today.year &&
      normalizedDate.month == today.month) {
    return (id: 'current_month', title: 'thisMonth');
  }
  final id = _dateId(date);
  return (id: id, title: id);
}

List<Expense> _sorted(List<Expense> expenses) {
  return [...expenses]..sort((a, b) => b.date.compareTo(a.date));
}

double _sum(List<Expense> expenses) {
  return expenses.fold<double>(0, (total, expense) => total + expense.amount);
}

String _fallback(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String _dateId(DateTime date) {
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().split('T').first;
}
