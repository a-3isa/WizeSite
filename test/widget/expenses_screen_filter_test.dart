import 'dart:async';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/data/expense_summary_providers.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeExpenseRepository implements ExpenseRepository {
  _FakeExpenseRepository(this.items);

  final List<Expense> items;

  @override
  Future<MutationResult> archiveExpense(String expenseId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createExpense({
    required String workspaceId,
    required String userId,
    required String projectId,
    String? projectName,
    required String category,
    required double amount,
    String? currency,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    double? projectTotalExpensesBefore,
    List<Attachment>? attachments,
  }) async {
    return const MutationResult();
  }

  @override
  Future<RecordPage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
    int pageSize = 20,
  }) async {
    return RecordPage<Expense>(items: items, hasMore: false);
  }

  @override
  Future<Expense?> getExpense(String expenseId) async {
    return items.firstWhere((expense) => expense.id == expenseId);
  }

  @override
  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) {
    return Stream.value(items);
  }
}

Expense _expense({
  required String id,
  required double amount,
  required String supplierName,
  String paymentStatus = 'unpaid',
  String description = '',
}) {
  return Expense(
    id: id,
    workspaceId: 'workspace_test',
    projectId: 'project_1',
    projectName: 'Project One',
    category: 'materials',
    amount: amount,
    currency: 'USD',
    date: DateTime.utc(2026, 5, 27),
    notes: '',
    description: description,
    supplierName: supplierName,
    entityName: supplierName,
    entityType: 'supplier',
    paymentMethod: 'cash',
    paymentStatus: paymentStatus,
    inputMethod: 'manual',
    transcript: '',
    source: '',
    storagePath: '',
    isArchived: false,
    attachments: const [],
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/expenses',
    routes: [
      GoRoute(
        path: '/expenses',
        builder: (context, state) =>
            const ExpensesScreen(projectId: 'project_1'),
      ),
      GoRoute(
        path: '/project/:id',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/expense/:id',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add-expense',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/add',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'ExpensesScreen shows loading content while first page resolves',
    (tester) async {
      final repository = _PendingExpenseRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
            expenseRepositoryProvider.overrideWithValue(repository),
            expenseQuickSummaryProvider.overrideWith(
              (ref, scope) => Stream.value(
                const ExpenseQuickSummary(
                  todayExpenses: 0,
                  weeklyExpenses: 0,
                  monthlyExpenses: 0,
                  transactionCount: 0,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );
      await tester.pump();

      expect(find.byType(AppLoadingSkeleton), findsOneWidget);
      expect(find.textContaining('Steel Supplier'), findsNothing);

      repository.completeFirstPage([
        _expense(id: 'expense_1', amount: 100, supplierName: 'Steel Supplier'),
      ]);
      await tester.pumpAndSettle();

      expect(find.byType(AppLoadingSkeleton), findsNothing);
      expect(find.textContaining('Steel Supplier'), findsOneWidget);
    },
  );

  testWidgets(
    'ExpensesScreen supports compact filters, grouping, bulk archive, and empty CTA',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeExpenseRepository([
        _expense(id: 'expense_1', amount: 100, supplierName: 'Steel Supplier'),
        _expense(id: 'expense_2', amount: 200, supplierName: 'Paint Crew'),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_test'),
            expenseRepositoryProvider.overrideWithValue(repository),
            expenseQuickSummaryProvider.overrideWith(
              (ref, scope) => Stream.value(
                const ExpenseQuickSummary(
                  todayExpenses: 100,
                  weeklyExpenses: 300,
                  monthlyExpenses: 600,
                  transactionCount: 2,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today expenses'), findsOneWidget);
      expect(find.text('Weekly expenses'), findsOneWidget);
      expect(find.text('Monthly expenses'), findsOneWidget);
      expect(find.text('Transactions'), findsWidgets);
      expect(find.textContaining('Steel Supplier'), findsOneWidget);
      expect(find.textContaining('Cash'), findsWidgets);
      expect(find.textContaining('Unpaid'), findsWidgets);
      expect(find.text('100 USD | Materials'), findsOneWidget);
      expect(find.text('200 USD | Materials'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Quick entry'), findsNothing);
      expect(find.text('Group by'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField).first, 'steel');
      await tester.pumpAndSettle();

      expect(find.text('Search: steel'), findsOneWidget);
      expect(find.byTooltip('Remove filter'), findsOneWidget);
      expect(find.text('100 USD | Materials'), findsOneWidget);
      expect(find.text('200 USD | Materials'), findsNothing);

      await tester.tap(find.byTooltip('Remove filter'));
      await tester.pumpAndSettle();

      expect(find.text('100 USD | Materials'), findsOneWidget);
      expect(find.text('200 USD | Materials'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'missing');
      await tester.pumpAndSettle();

      expect(find.text('No matching results.'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);

      await tester.ensureVisible(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('100 USD | Materials'));
      await tester.pump();

      expect(find.byTooltip('Archive selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Archive selected'));
      await tester.pumpAndSettle();
      expect(find.text('Archive 1 selected items?'), findsOneWidget);
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      expect(find.text('100 USD | Materials'), findsNothing);

      await tester.ensureVisible(find.text('200 USD | Materials'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('200 USD | Materials'));
      await tester.tap(find.byTooltip('Archive selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();

      expect(find.text('No expenses yet.'), findsOneWidget);
      expect(find.text('Add Expense'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PendingExpenseRepository extends _FakeExpenseRepository {
  _PendingExpenseRepository() : super(const []);

  final _firstPageCompleter = Completer<RecordPage<Expense>>();

  @override
  Future<RecordPage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    Object? cursor,
    int pageSize = 20,
  }) {
    return _firstPageCompleter.future;
  }

  void completeFirstPage(List<Expense> items) {
    _firstPageCompleter.complete(
      RecordPage<Expense>(items: items, hasMore: false),
    );
  }
}
