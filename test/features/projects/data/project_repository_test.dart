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

  test('an offline-queued create with no contract shows no fabricated zero', () async {
    final firestore = FakeFirebaseFirestore();
    await queue.enqueue(
      type: OfflineActionTypes.createProject,
      payload: {
        'workspaceId': 'workspace_1',
        'name': 'Expense Only Job',
        'clientName': '',
        'contractValue': null,
        'completionPercentage': 0,
      },
    );

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    // The stream merges two sources (Firestore + the offline queue) and emits
    // on each, so the first emission can precede the queue listener firing.
    final projects = await repository
        .watchProjects('workspace_1')
        .firstWhere((items) => items.isNotEmpty)
        .timeout(const Duration(seconds: 5));

    expect(projects, hasLength(1));
    final optimistic = projects.single;
    expect(optimistic.name, 'Expense Only Job');
    // A `?? 0` on the optimistic placeholder would show the user a contract
    // amount they never entered, for as long as the action stays queued.
    expect(optimistic.contractValue, isNull);
    expect(optimistic.hasContractValue, isFalse);
    expect(optimistic.isExpenseLedger, isTrue);
  });

  test('hasAnyPayment ignores archived payments', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').doc('payment_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'amount': 500,
      'isArchived': true,
    });

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    // Archiving is the only removal this app offers, so an archived payment
    // must not keep the contract value permanently locked.
    expect(await repository.hasAnyPayment('project_1'), isFalse);
  });

  test('hasAnyPayment sees an active payment', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').doc('payment_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'amount': 500,
      'isArchived': false,
    });

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    expect(await repository.hasAnyPayment('project_1'), isTrue);
  });

  test('hasAnyPayment counts a payment still queued offline', () async {
    final firestore = FakeFirebaseFirestore();
    await queue.enqueue(
      type: OfflineActionTypes.createPayment,
      payload: {
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'amount': 500,
      },
    );

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    // Otherwise a user could clear the contract offline and strand the queued
    // payment on sync.
    expect(await repository.hasAnyPayment('project_1'), isTrue);
  });

  test('hasAnyPayment ignores payments belonging to another project', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').doc('payment_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_other',
      'amount': 500,
      'isArchived': false,
    });

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    expect(await repository.hasAnyPayment('project_1'), isFalse);
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

  test('active project warm stream is capped to 50 most recent rows', () async {
    final firestore = FakeFirebaseFirestore();
    for (var index = 0; index < 60; index++) {
      await firestore.collection('projects').doc('project_$index').set({
        'workspaceId': 'workspace_1',
        'name': 'Project $index',
        'clientName': 'Client',
        'contractValue': 100,
        'status': 'active',
        'completionPercentage': 0,
        'totalExpenses': 0,
        'totalPayments': 0,
        'netProfit': 0,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 1, 1).add(Duration(days: index)),
      });
    }

    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final projects = await repository.watchProjects('workspace_1').first;

    expect(projects, hasLength(50));
    expect(projects.first.id, 'project_59');
    expect(projects.last.id, 'project_10');
  });

  test('name browse pages use stable project-field ordering', () async {
    final firestore = FakeFirebaseFirestore();
    for (final entry in [
      ('project_c', 'Beta'),
      ('project_b', 'Alpha'),
      ('project_a', 'Alpha'),
    ]) {
      await firestore.collection('projects').doc(entry.$1).set({
        'id': entry.$1,
        'workspaceId': 'workspace_1',
        'name': entry.$2,
        'clientName': 'Client',
        'contractValue': 100,
        'status': 'active',
        'completionPercentage': 0,
        'totalExpenses': 0,
        'totalPayments': 0,
        'netProfit': 0,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 1, 1),
      });
    }
    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final first = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.name,
        pageSize: 2,
      ),
    );
    final second = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.name,
        pageSize: 2,
      ),
      cursor: first.nextCursor,
    );

    expect(first.items.map((item) => item.id), ['project_a', 'project_b']);
    expect(second.items.map((item) => item.id), ['project_c']);
  });

  test('financial browse preserves global metric order across pages', () async {
    final firestore = FakeFirebaseFirestore();
    for (final entry in [
      ('project_a', 'Alpha', 1000.0),
      ('project_b', 'Beta', 900.0),
      ('project_c', 'Gamma', 800.0),
    ]) {
      await firestore.collection('projects').doc(entry.$1).set({
        'id': entry.$1,
        'workspaceId': 'workspace_1',
        'name': entry.$2,
        'clientName': 'Client',
        'contractValue': 100,
        'status': 'active',
        'completionPercentage': 0,
        'totalExpenses': 0,
        'totalPayments': 0,
        'netProfit': 0,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 1, 1),
      });
      await firestore.collection('project_metrics').doc(entry.$1).set({
        'workspaceId': 'workspace_1',
        'projectId': entry.$1,
        'projectName': entry.$2,
        'status': 'active',
        'isArchived': false,
        'totalExpenses': entry.$3,
        'totalIncome': entry.$3 + 200,
        'net': 200,
        'netProfit': 200,
      });
    }
    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final first = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.highestExpense,
        pageSize: 2,
      ),
    );
    final second = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.highestExpense,
        pageSize: 2,
      ),
      cursor: first.nextCursor,
    );

    expect(first.items.map((item) => item.id), ['project_a', 'project_b']);
    expect(first.items.map((item) => item.totalExpenses), [1000, 900]);
    expect(second.items.map((item) => item.id), ['project_c']);
    expect(second.items.single.totalExpenses, 800);
  });

  test('recent browse uses project id as a stable date tie-breaker', () async {
    final firestore = FakeFirebaseFirestore();
    for (final id in ['project_a', 'project_b', 'project_c']) {
      await firestore.collection('projects').doc(id).set({
        'id': id,
        'workspaceId': 'workspace_1',
        'name': id,
        'clientName': 'Client',
        'contractValue': 100,
        'status': id == 'project_c' ? 'completed' : 'active',
        'completionPercentage': 0,
        'totalExpenses': 0,
        'totalPayments': 0,
        'netProfit': 0,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 6, 1),
      });
    }
    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final first = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.recent,
        pageSize: 2,
      ),
    );
    final second = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.recent,
        pageSize: 2,
      ),
      cursor: first.nextCursor,
    );
    final completed = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(workspaceId: 'workspace_1', status: 'completed'),
    );

    expect(first.items.map((item) => item.id), ['project_a', 'project_b']);
    expect(second.items.map((item) => item.id), ['project_c']);
    expect(completed.items.map((item) => item.id), ['project_c']);
  });

  test(
    'recent browse net profit reflects project_metrics not stale doc',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('projects').doc('project_1').set({
        'id': 'project_1',
        'workspaceId': 'workspace_1',
        'name': 'Tower A',
        'clientName': 'Client',
        'contractValue': 250000,
        'status': 'active',
        'completionPercentage': 0,
        // Stale denormalized values on the project doc.
        'totalExpenses': 16570,
        'totalPayments': 22820,
        'netProfit': 6250,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 6, 1),
      });
      // Authoritative recomputed metrics differ from the stale doc.
      await firestore.collection('project_metrics').doc('project_1').set({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'totalExpenses': 20000,
        'totalPayments': 30000,
        'netProfit': 10000,
      });

      final repository = FirebaseProjectRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchProjectBrowsePage(
        const ProjectBrowseQuery(
          workspaceId: 'workspace_1',
          sort: ProjectBrowseSort.recent,
        ),
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.totalExpenses, 20000);
      expect(page.items.single.totalPayments, 30000);
      expect(page.items.single.netProfit, 10000);
    },
  );

  test('archived project page excludes active projects', () async {
    final firestore = FakeFirebaseFirestore();
    for (final archived in [false, true]) {
      final id = archived ? 'archived' : 'active';
      await firestore.collection('projects').doc(id).set({
        'id': id,
        'workspaceId': 'workspace_1',
        'name': id,
        'clientName': 'Client',
        'contractValue': 100,
        'status': 'completed',
        'completionPercentage': 100,
        'totalExpenses': 0,
        'totalPayments': 0,
        'netProfit': 0,
        'isArchived': archived,
        'createdAt': DateTime.utc(2026, 6, 1),
      });
    }
    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final page = await repository.fetchArchivedProjectsPage('workspace_1');

    expect(page.items.map((item) => item.id), ['archived']);
  });

  test('income and net sorts use their maintained metric fields', () async {
    final firestore = FakeFirebaseFirestore();
    final metrics = {
      'project_a': (expenses: 1000, income: 100, net: -900),
      'project_b': (expenses: 900, income: 2000, net: 1100),
      'project_c': (expenses: 800, income: 1000, net: 200),
    };
    for (final entry in metrics.entries) {
      await firestore.collection('projects').doc(entry.key).set({
        'id': entry.key,
        'workspaceId': 'workspace_1',
        'name': entry.key,
        'clientName': 'Client',
        'contractValue': 100,
        'status': 'active',
        'completionPercentage': 0,
        'isArchived': false,
        'createdAt': DateTime.utc(2026, 6, 1),
      });
      await firestore.collection('project_metrics').doc(entry.key).set({
        'workspaceId': 'workspace_1',
        'projectId': entry.key,
        'projectName': entry.key,
        'status': 'active',
        'isArchived': false,
        'totalExpenses': entry.value.expenses,
        'totalIncome': entry.value.income,
        'net': entry.value.net,
      });
    }
    final repository = FirebaseProjectRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final income = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.highestIncome,
      ),
    );
    final net = await repository.fetchProjectBrowsePage(
      const ProjectBrowseQuery(
        workspaceId: 'workspace_1',
        sort: ProjectBrowseSort.highestNet,
      ),
    );

    expect(income.items.map((item) => item.id), [
      'project_b',
      'project_c',
      'project_a',
    ]);
    expect(net.items.map((item) => item.id), [
      'project_b',
      'project_c',
      'project_a',
    ]);
  });
}
