import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('project_repository_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('project reads include visible optimistic finance deltas', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('projects').doc('project_1').set({
      'workspaceId': 'workspace_1',
      'name': 'Tower A',
      'clientName': 'Client',
      'contractValue': 250000,
      'status': 'active',
      'completionPercentage': 0,
      'totalExpenses': 16570,
      'totalPayments': 22820,
      'netProfit': 6250,
      'isArchived': false,
      'createdAt': DateTime.utc(2026, 5, 20),
    });
    await firestore.collection('project_metrics').doc('project_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'totalExpenses': 16570,
      'totalPayments': 22820,
      'netProfit': 6250,
    });
    await queue.enqueue(
      type: OfflineActionTypes.createExpense,
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'amount': 100,
      },
    );

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final page = await repository.fetchProjectsPage('workspace_1');

    expect(page.items, hasLength(1));
    expect(page.items.single.totalExpenses, 16670);
    expect(page.items.single.netProfit, 6150);
  });

  test(
    'project reads do not reapply deltas already reflected in metrics',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('projects').doc('project_1').set({
        'workspaceId': 'workspace_1',
        'name': 'Tower A',
        'clientName': 'Client',
        'contractValue': 250000,
        'status': 'active',
        'completionPercentage': 0,
        'totalExpenses': 16570,
        'totalPayments': 22820,
        'netProfit': 6250,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 5, 20),
      });
      await firestore.collection('project_metrics').doc('project_1').set({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'totalExpenses': 16670,
        'totalPayments': 22820,
        'netProfit': 6150,
      });
      await queue.enqueue(
        type: OfflineActionTypes.createExpense,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'amount': 100,
          'projectTotalExpensesBefore': 16570,
        },
      );

      final repository = FirebaseProjectRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchProjectsPage('workspace_1');

      expect(page.items, hasLength(1));
      expect(page.items.single.totalExpenses, 16670);
      expect(page.items.single.netProfit, 6150);
    },
  );

  test(
    'project reads keep synced payment deltas until metrics reflect them',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('projects').doc('project_1').set({
        'workspaceId': 'workspace_1',
        'name': 'Tower A',
        'clientName': 'Client',
        'contractValue': 250000,
        'status': 'active',
        'completionPercentage': 0,
        'totalExpenses': 0,
        'totalPayments': 200,
        'netProfit': 200,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 5, 20),
      });
      await firestore.collection('project_metrics').doc('project_1').set({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'totalExpenses': 0,
        'totalPayments': 200,
        'netProfit': 200,
      });
      final action = await queue.enqueue(
        type: OfflineActionTypes.createPayment,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'amount': 100,
          'projectTotalPaymentsBefore': 200,
          'projectTotalPaymentsAfter': 300,
        },
      );
      await queue.save(
        action.copyWith(
          status: OfflineActionStatus.synced,
          syncedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      );

      final repository = FirebaseProjectRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchProjectsPage('workspace_1');

      expect(page.items, hasLength(1));
      expect(page.items.single.totalPayments, 300);
      expect(page.items.single.netProfit, 300);
    },
  );

  test('project reads do not double count reflected synced payments', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('projects').doc('project_1').set({
      'workspaceId': 'workspace_1',
      'name': 'Tower A',
      'clientName': 'Client',
      'contractValue': 250000,
      'status': 'active',
      'completionPercentage': 0,
      'totalExpenses': 0,
      'totalPayments': 200,
      'netProfit': 200,
      'isArchived': false,
      'createdAt': DateTime.utc(2026, 5, 20),
    });
    await firestore.collection('project_metrics').doc('project_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'totalExpenses': 0,
      'totalPayments': 300,
      'netProfit': 300,
    });
    final action = await queue.enqueue(
      type: OfflineActionTypes.createPayment,
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'amount': 100,
        'projectTotalPaymentsBefore': 200,
        'projectTotalPaymentsAfter': 300,
      },
    );
    await queue.save(
      action.copyWith(
        status: OfflineActionStatus.synced,
        syncedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    );

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final page = await repository.fetchProjectsPage('workspace_1');

    expect(page.items, hasLength(1));
    expect(page.items.single.totalPayments, 300);
    expect(page.items.single.netProfit, 300);
  });
}
