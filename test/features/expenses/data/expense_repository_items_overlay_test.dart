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

/// Feature 005: queued offline actions show their receipt items before sync
/// (T014), and actions queued by an older app build stay legacy (T032).
void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;
  late LocalTestDb local;
  late LocalExpenseRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('expense_items_overlay_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_expense_items');
    queue = OfflineActionQueue(box);
    local = await LocalTestDb.open();
    repository = LocalExpenseRepository(
      _MockWorkspaceMutationService(),
      queue,
      Future.value(local.db),
    );
    await local.seedRows('expenses', [
      {
        'id': 'e_plumbing',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'amount': 240,
        'date': '2026-10-01 08:00:00Z',
        'category': 'materials',
        'description': 'سباكه شهر 10',
        'is_archived': 0,
        'attachments': '[]',
        'items':
            '[{"id":"a","name":"حنفية","amount":100},'
            '{"id":"b","name":"جلبه","amount":50},'
            '{"id":"c","name":"ماسورة","amount":90}]',
      },
    ]);
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_expense_items');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('synced row exposes its items in order', () async {
    final items = await repository.watchExpenses('ws_1', 'p1').first;
    final plumbing = items.singleWhere((e) => e.id == 'e_plumbing');
    expect(plumbing.items.map((i) => i.name), ['حنفية', 'جلبه', 'ماسورة']);
    expect(plumbing.title, 'سباكه شهر 10');
  });

  test('pending create with items shows them optimistically', () async {
    await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'ws_1',
        'projectId': 'p1',
        'amount': 150,
        'category': 'materials',
        'date': DateTime.utc(2026, 10, 5).toIso8601String(),
        'description': 'كهربا',
        'inputMethod': 'text',
        'items': [
          {'id': 'x1', 'name': 'سلك', 'amount': 100},
          {'id': 'x2', 'name': 'مفاتيح', 'amount': 50},
        ],
      },
    );
    final items = await repository.watchExpenses('ws_1', 'p1').first;
    final pending = items.first;
    expect(pending.id, startsWith('pending_'));
    expect(pending.items.map((i) => i.name), ['سلك', 'مفاتيح']);
    expect(pending.inputMethod, 'text');
  });

  test('pending update with items replaces the synced items', () async {
    await queue.enqueue(
      type: OfflineActionTypes.updateExpense,
      payload: {
        'workspaceId': 'ws_1',
        'projectId': 'p1',
        'expenseId': 'e_plumbing',
        'amount': 255,
        'category': 'materials',
        'date': DateTime.utc(2026, 10, 1, 8).toIso8601String(),
        'items': [
          {'id': 'a', 'name': 'حنفية', 'amount': 100},
          {'id': 'b', 'name': 'جلبه', 'amount': 50},
          {'id': 'c', 'name': 'ماسورة', 'amount': 95},
          {'id': 'd', 'name': 'شريط تيفلون', 'amount': 10},
        ],
      },
    );
    final items = await repository.watchExpenses('ws_1', 'p1').first;
    final plumbing = items.singleWhere((e) => e.id == 'e_plumbing');
    expect(plumbing.amount, 255);
    expect(plumbing.items, hasLength(4));
    expect(plumbing.items.last.name, 'شريط تيفلون');
  });

  test('pending update without items keeps the synced items', () async {
    await queue.enqueue(
      type: OfflineActionTypes.updateExpense,
      payload: {
        'workspaceId': 'ws_1',
        'projectId': 'p1',
        'expenseId': 'e_plumbing',
        'amount': 240,
        'category': 'materials',
        'date': DateTime.utc(2026, 10, 1, 8).toIso8601String(),
        'paymentStatus': 'paid',
      },
    );
    final items = await repository.watchExpenses('ws_1', 'p1').first;
    final plumbing = items.singleWhere((e) => e.id == 'e_plumbing');
    expect(plumbing.items, hasLength(3));
    expect(plumbing.paymentStatus, 'paid');
  });

  test(
    'create queued by an older app build (no items) stays a legacy expense',
    () async {
      await queue.enqueue(
        type: OfflineActionTypes.createExpense,
        payload: {
          'workspaceId': 'ws_1',
          'projectId': 'p1',
          'amount': 7.5,
          'category': 'other',
          'date': DateTime.utc(2026, 10, 6).toIso8601String(),
          'notes': 'offline',
        },
      );
      final items = await repository.watchExpenses('ws_1', 'p1').first;
      final pending = items.first;
      expect(pending.items, isEmpty);
      expect(pending.effectiveItems, hasLength(1));
      expect(pending.effectiveItems.single.amount, 7.5);
      expect(pending.inputMethod, 'manual');
    },
  );
}
