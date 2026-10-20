import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/expense_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feature 005: the detail screen lists every receipt item with the total
/// (T021) and its duplicate action copies the items with new ids (T022).
void main() {
  testWidgets('detail shows the title, each item and the total', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeExpenseRepository(), _plumbing()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa_expense_detail_title')), findsOneWidget);
    expect(find.text('سباكه شهر 10'), findsOneWidget);
    for (final name in ['حنفية', 'جلبه', 'ماسورة']) {
      expect(find.textContaining(name), findsOneWidget);
    }
    expect(find.textContaining('× 2'), findsOneWidget, reason: 'quantity');
    expect(find.byKey(const Key('qa_expense_detail_total')), findsOneWidget);
  });

  testWidgets('a legacy expense shows one item named after its category', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeExpenseRepository(), _plumbing(items: const [], title: '')),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations(const Locale('en'));
    final section = find.byKey(const Key('qa_expense_detail_items'));
    expect(
      find.descendant(
        of: section,
        matching: find.textContaining(l10n.expenseCategoryLabel('materials')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('duplicate copies the items with new ids and the same title', (
    tester,
  ) async {
    final repo = _FakeExpenseRepository();
    await tester.pumpWidget(_app(repo, _plumbing()));
    await tester.pumpAndSettle();
    await _tapDuplicate(tester);

    final created = repo.lastCreate!;
    expect(created['description'], 'سباكه شهر 10');
    expect(created['amount'], 240);
    final items = created['items']! as List<Map<String, dynamic>>;
    expect(items.map((i) => i['name']), ['حنفية', 'جلبه', 'ماسورة']);
    expect(
      items.map((i) => i['id']).toSet().intersection({'a', 'b', 'c'}),
      isEmpty,
      reason: 'each copy gets a fresh item id',
    );
  });

  testWidgets('duplicating a legacy expense sends no items', (tester) async {
    final repo = _FakeExpenseRepository();
    await tester.pumpWidget(_app(repo, _plumbing(items: const [])));
    await tester.pumpAndSettle();
    await _tapDuplicate(tester);
    expect(repo.lastCreate!.containsKey('items'), isTrue);
    expect(repo.lastCreate!['items'], isNull);
  });
}

Future<void> _tapDuplicate(WidgetTester tester) async {
  final button = find.text('Duplicate');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Expense _plumbing({
  List<ExpenseItem> items = const [
    ExpenseItem(id: 'a', name: 'حنفية', amount: 100, quantity: 2),
    ExpenseItem(id: 'b', name: 'جلبه', amount: 50),
    ExpenseItem(id: 'c', name: 'ماسورة', amount: 90),
  ],
  String title = 'سباكه شهر 10',
}) {
  return Expense(
    id: 'e_plumbing',
    workspaceId: 'workspace_1',
    projectId: 'project_1',
    projectName: 'Tower',
    category: 'materials',
    amount: 240,
    currency: 'EGP',
    date: DateTime.utc(2026, 10, 1),
    notes: '',
    description: title,
    supplierName: '',
    paymentMethod: 'cash',
    inputMethod: 'manual',
    transcript: '',
    source: '',
    storagePath: '',
    isArchived: false,
    attachments: const [],
    items: items,
  );
}

Widget _app(_FakeExpenseRepository repo, Expense expense) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      expenseRepositoryProvider.overrideWithValue(repo),
      expenseDetailsProvider.overrideWith((ref, id) async => expense),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ExpenseDetailScreen(expenseId: 'e_plumbing'),
    ),
  );
}

class _FakeExpenseRepository implements ExpenseRepository {
  Map<String, Object?>? lastCreate;

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
    List<Map<String, dynamic>>? items,
    String inputMethod = 'manual',
    String? transcript,
    String? source,
  }) async {
    lastCreate = {
      'description': description,
      'amount': amount,
      'items': items,
    };
    return const MutationResult();
  }

  @override
  Future<MutationResult> archiveExpense(String expenseId) async =>
      const MutationResult();

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
  }) async => const RecordPage(items: [], hasMore: false);

  @override
  Future<Expense?> getExpense(String expenseId) async => null;

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
    List<Map<String, dynamic>>? items,
  }) async {}

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) =>
      const Stream.empty();
}
