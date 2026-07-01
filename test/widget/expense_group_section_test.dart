import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/models/expense_group.dart';
import 'package:buildtrack_app/features/expenses/presentation/widgets/expense_group_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Expense expense(String id) {
    return Expense(
      id: id,
      workspaceId: 'workspace_1',
      projectId: 'project_1',
      projectName: 'Project One',
      category: 'materials',
      amount: 25,
      currency: 'USD',
      date: DateTime.utc(2026, 5, 27),
      notes: '',
      supplierName: 'Steel Supplier',
      paymentMethod: 'cash',
      inputMethod: 'manual',
      transcript: '',
      source: '',
      storagePath: '',
      isArchived: false,
      attachments: const [],
    );
  }

  testWidgets('toggles group body while showing total and count', (
    tester,
  ) async {
    final group = ExpenseGroup(
      id: 'materials',
      title: 'Materials',
      totalAmount: 50,
      transactionCount: 2,
      items: [expense('expense_1'), expense('expense_2')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseGroupSection(
            group: group,
            itemBuilder: (context, expense) => Text(expense.id),
          ),
        ),
      ),
    );

    expect(find.text('Materials'), findsOneWidget);
    expect(find.text('2 transactions'), findsOneWidget);
    expect(find.textContaining('50'), findsOneWidget);
    expect(find.text('expense_1'), findsOneWidget);

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.text('expense_1'), findsNothing);
  });
}
