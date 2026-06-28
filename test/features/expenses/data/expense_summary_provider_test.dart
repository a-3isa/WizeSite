import 'dart:io';

import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/data/expense_summary_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Future<T> _readStreamProvider<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
) {
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container.read(provider.future);
}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'expense_summary_provider_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('expense_summary_provider_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('expense_summary_provider_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('merges pending expense deltas into scoped quick summary', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('project_summaries').doc('summary_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'todayExpenses': 100,
      'weeklyExpenses': 300,
      'monthlyExpenses': 900,
      'transactionCount': 7,
      'updatedAt': DateTime.utc(2026, 5, 27),
    });
    await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'amount': 25,
        'date': DateTime.utc(2026, 5, 27, 10).toIso8601String(),
      },
    );
    await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'other_project',
        'amount': 50,
        'date': DateTime.utc(2026, 5, 27, 10).toIso8601String(),
      },
    );

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        offlineActionQueueProvider.overrideWithValue(queue),
      ],
    );
    addTearDown(container.dispose);

    final summary = await _readStreamProvider(
      container,
      expenseQuickSummaryProvider(
        ExpenseSummaryScope(
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          now: DateTime.utc(2026, 5, 27),
        ),
      ),
    );

    expect(summary.todayExpenses, 125);
    expect(summary.weeklyExpenses, 325);
    expect(summary.monthlyExpenses, 925);
    expect(summary.transactionCount, 8);
  });

  test('does not double count synced queued expenses', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('project_summaries').doc('summary_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'todayExpenses': 100,
      'weeklyExpenses': 300,
      'monthlyExpenses': 900,
      'transactionCount': 7,
      'updatedAt': DateTime.utc(2026, 5, 27),
    });
    final action = await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'amount': 25,
        'date': DateTime.utc(2026, 5, 27, 10).toIso8601String(),
      },
    );
    await queue.save(
      action.copyWith(
        status: OfflineActionStatus.synced,
        syncedAt: DateTime.utc(2026, 5, 27, 10, 1),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        offlineActionQueueProvider.overrideWithValue(queue),
      ],
    );
    addTearDown(container.dispose);

    final summary = await _readStreamProvider(
      container,
      expenseQuickSummaryProvider(
        ExpenseSummaryScope(
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          now: DateTime.utc(2026, 5, 27),
        ),
      ),
    );

    expect(summary.todayExpenses, 100);
    expect(summary.weeklyExpenses, 300);
    expect(summary.monthlyExpenses, 900);
    expect(summary.transactionCount, 7);
  });
}
