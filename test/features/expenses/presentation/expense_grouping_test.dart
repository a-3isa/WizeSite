import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/models/expense_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Expense expense({
    required String id,
    required double amount,
    required DateTime date,
    String category = 'materials',
    String entityName = 'Steel Supplier',
    String supplierName = '',
    String paymentMethod = 'cash',
  }) {
    return Expense(
      id: id,
      workspaceId: 'workspace_1',
      projectId: 'project_1',
      projectName: 'Project One',
      category: category,
      amount: amount,
      currency: 'USD',
      date: date,
      notes: '',
      supplierName: supplierName,
      entityName: entityName,
      paymentMethod: paymentMethod,
      inputMethod: 'manual',
      transcript: '',
      source: '',
      storagePath: '',
      isArchived: false,
      attachments: const [],
    );
  }

  test('groups expenses by category with totals and counts', () {
    final groups = groupExpenses([
      expense(id: '1', amount: 10, date: DateTime.utc(2026, 5, 27)),
      expense(
        id: '2',
        amount: 15,
        date: DateTime.utc(2026, 5, 27),
        category: 'labor',
      ),
      expense(id: '3', amount: 5, date: DateTime.utc(2026, 5, 26)),
    ], ExpenseGroupMode.category);

    expect(groups, hasLength(2));
    expect(groups.first.id, 'materials');
    expect(groups.first.totalAmount, 15);
    expect(groups.first.transactionCount, 2);
    expect(groups.last.id, 'labor');
  });

  test('groups expenses by entity and uses unassigned fallback', () {
    final groups = groupExpenses([
      expense(id: '1', amount: 10, date: DateTime.utc(2026, 5, 27)),
      expense(
        id: '2',
        amount: 15,
        date: DateTime.utc(2026, 5, 27),
        entityName: '',
        supplierName: '',
      ),
    ], ExpenseGroupMode.entity);

    expect(groups.map((group) => group.title), [
      'Steel Supplier',
      'Unassigned',
    ]);
  });

  test('groups expenses by exact and relative date', () {
    final today = DateTime.utc(2026, 5, 27);
    final items = [
      expense(id: '1', amount: 10, date: today),
      expense(
        id: '2',
        amount: 15,
        date: today.subtract(const Duration(days: 1)),
      ),
    ];

    final exactGroups = groupExpenses(items, ExpenseGroupMode.date);
    expect(exactGroups.map((group) => group.title), [
      '2026-05-27',
      '2026-05-26',
    ]);

    final relativeGroups = groupExpenses(
      items,
      ExpenseGroupMode.relativeDate,
      now: today,
    );
    expect(relativeGroups.map((group) => group.title), ['Today', 'Yesterday']);
  });
}
