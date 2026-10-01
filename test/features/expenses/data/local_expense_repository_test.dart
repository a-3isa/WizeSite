import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/local_db.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late LocalTestDb local;
  late LocalExpenseRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_expenses_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_local_expenses');
    queue = OfflineActionQueue(box);
    local = await LocalTestDb.open();
    repository = LocalExpenseRepository(
      _MockWorkspaceMutationService(),
      queue,
      Future.value(local.db),
    );
    // Replica timestamp text uses a space separator, like replicated timestamptz.
    Map<String, Object?> expense(
      String id,
      String date,
      String category, {
      double amount = 10,
      int archived = 0,
      String project = 'p1',
    }) => {
      'id': id,
      'workspace_id': 'ws_1',
      'project_id': project,
      'amount': amount,
      'date': date,
      'category': category,
      'is_archived': archived,
      'notes': 'ملاحظة $id',
      'attachments': '[]',
    };
    await local.seedRows('expenses', [
      expense('e1', '2026-05-01 08:00:00Z', 'materials'),
      expense('e2', '2026-05-15 08:00:00Z', 'transport'),
      expense('e3', '2026-06-01 08:00:00Z', 'materials', amount: 99),
      expense('e_arch', '2026-06-02 08:00:00Z', 'materials', archived: 1),
      expense('e_other', '2026-06-03 08:00:00Z', 'materials', project: 'p2'),
    ]);
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_local_expenses');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('watchExpenses: project scope, active only, newest first', () async {
    final items = await repository.watchExpenses('ws_1', 'p1').first;
    expect(items.map((e) => e.id), ['e3', 'e2', 'e1']);
    expect(items.first.amount, 99);
    expect(items.first.date, DateTime.utc(2026, 6, 1, 8));
    expect(items.first.notes, 'ملاحظة e3');
  });

  test('queued offline expense appears optimistically at the top', () async {
    await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'ws_1',
        'projectId': 'p1',
        'amount': 7.5,
        'category': 'other',
        'date': DateTime.utc(2026, 6, 5).toIso8601String(),
        'notes': 'offline',
      },
    );
    final items = await repository.watchExpenses('ws_1', 'p1').first;
    expect(items.first.id, startsWith('pending_'));
    expect(items.length, 4);
  });

  test(
    'page filters: category and a date range across timestamp formats',
    () async {
      final page = await repository.fetchExpensesPage(
        'ws_1',
        projectId: 'p1',
        category: 'materials',
        startDate: DateTime.utc(2026, 5, 10),
        endDate: DateTime.utc(2026, 6, 30),
      );
      expect(page.items.map((e) => e.id), ['e3']);
    },
  );

  test('keyset paging is gap-free', () async {
    final first = await repository.fetchExpensesPage(
      'ws_1',
      projectId: 'p1',
      pageSize: 2,
    );
    expect(first.items.map((e) => e.id), ['e3', 'e2']);
    expect(first.hasMore, isTrue);
    final second = await repository.fetchExpensesPage(
      'ws_1',
      projectId: 'p1',
      pageSize: 2,
      cursor: first.nextCursor,
    );
    expect(second.items.map((e) => e.id), ['e1']);
    expect(second.hasMore, isFalse);
  });

  test('getExpense', () async {
    expect((await repository.getExpense('e2'))?.category, 'transport');
    expect(await repository.getExpense('missing'), isNull);
  });
}
