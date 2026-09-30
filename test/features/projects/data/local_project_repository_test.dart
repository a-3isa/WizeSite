import 'dart:io';

import 'package:buildtrack_app/core/pagination/local_page.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
  late LocalProjectRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_projects_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_local_projects');
    queue = OfflineActionQueue(box);
    local = await LocalTestDb.open();
    repository = LocalProjectRepository(
      FakeFirebaseFirestore(),
      _MockWorkspaceMutationService(),
      queue,
      Future.value(local.db),
    );
    await local.seedRows('projects', [
      {
        'id': 'p1',
        'workspace_id': 'ws_1',
        'name': 'Tower',
        'status': 'active',
        'contract_value': 1000.0,
        'is_archived': 0,
        'created_at': '2026-05-01T00:00:00.000Z',
      },
      {
        'id': 'p2',
        'workspace_id': 'ws_1',
        'name': 'Annex',
        'status': 'active',
        'is_archived': 0,
        'created_at': '2026-06-01T00:00:00.000Z',
      },
      {
        'id': 'p3',
        'workspace_id': 'ws_1',
        'name': 'Old',
        'status': 'completed',
        'is_archived': 1,
        'created_at': '2026-01-01T00:00:00.000Z',
      },
      {
        'id': 'x1',
        'workspace_id': 'ws_2',
        'name': 'Other workspace',
        'is_archived': 0,
        'created_at': '2026-07-01T00:00:00.000Z',
      },
    ]);
    await local.seedRows('project_metrics', [
      {
        'id': 'p1',
        'workspace_id': 'ws_1',
        'payload':
            '{"totalExpenses":300,"totalPayments":500,"netProfit":200,"totalIncome":500,"net":200}',
      },
      {
        'id': 'p2',
        'workspace_id': 'ws_1',
        'payload':
            '{"totalExpenses":900,"totalPayments":0,"netProfit":-900,"totalIncome":0,"net":-900}',
      },
    ]);
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_local_projects');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'watchProjects: active projects of the workspace, newest first, with metrics',
    () async {
      final projects = await repository.watchProjects('ws_1').first;
      expect(projects.map((p) => p.id), ['p2', 'p1']);
      expect(projects.last.totalExpenses, 300);
      expect(projects.last.contractValue, 1000);
      expect(projects.first.contractValue, isNull);
    },
  );

  test('watchArchivedProjects and watchAllProjects', () async {
    expect(
      (await repository.watchArchivedProjects('ws_1').first).map((p) => p.id),
      ['p3'],
    );
    expect((await repository.watchAllProjects('ws_1').first).map((p) => p.id), [
      'p2',
      'p1',
      'p3',
    ]);
  });

  test('watchProject emits updates when the replica changes', () async {
    final stream = repository.watchProject('p1');
    final first = await stream.first;
    expect(first?.name, 'Tower');
    final updates = stream.where((p) => p?.name == 'Tower 2').first;
    await local.db.execute(
      "UPDATE projects SET name = 'Tower 2' WHERE id = 'p1'",
    );
    expect((await updates)?.name, 'Tower 2');
  });

  test('getProject and missing project', () async {
    expect((await repository.getProject('p2'))?.totalExpenses, 900);
    expect(await repository.getProject('nope'), isNull);
  });

  test('fetchProjectsPage pages by keyset without gaps', () async {
    final first = await repository.fetchProjectsPage('ws_1', pageSize: 1);
    expect(first.items.map((p) => p.id), ['p2']);
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, isA<LocalPageCursor>());
    final second = await repository.fetchProjectsPage(
      'ws_1',
      pageSize: 1,
      cursor: first.nextCursor,
    );
    expect(second.items.map((p) => p.id), ['p1']);
    expect(second.hasMore, isFalse);
  });

  test(
    'browse: name sort ascending, financial sort by recomputed totals, status filter',
    () async {
      final byName = await repository.fetchProjectBrowsePage(
        const ProjectBrowseQuery(
          workspaceId: 'ws_1',
          sort: ProjectBrowseSort.name,
        ),
      );
      expect(byName.items.map((p) => p.id), [
        'p2',
        'p1',
      ], reason: 'Annex < Tower');

      final byExpense = await repository.fetchProjectBrowsePage(
        const ProjectBrowseQuery(
          workspaceId: 'ws_1',
          sort: ProjectBrowseSort.highestExpense,
        ),
      );
      expect(byExpense.items.map((p) => p.id), ['p2', 'p1']);

      final completed = await repository.fetchProjectBrowsePage(
        const ProjectBrowseQuery(
          workspaceId: 'ws_1',
          status: 'completed',
          includeArchived: true,
        ),
      );
      expect(completed.items.map((p) => p.id), ['p3']);
    },
  );

  test(
    'hasAnyPayment ignores archived payments and counts queued ones',
    () async {
      await local.seedRows('payments', [
        {
          'id': 'pay1',
          'workspace_id': 'ws_1',
          'project_id': 'p2',
          'amount': 5.0,
          'is_archived': 1,
        },
      ]);
      expect(await repository.hasAnyPayment('p2'), isFalse);
      await local.seedRows('payments', [
        {
          'id': 'pay2',
          'workspace_id': 'ws_1',
          'project_id': 'p2',
          'amount': 5.0,
          'is_archived': 0,
        },
      ]);
      expect(await repository.hasAnyPayment('p2'), isTrue);

      await queue.enqueue(
        type: OfflineActionTypes.createPayment,
        payload: {'projectId': 'p1'},
      );
      expect(await repository.hasAnyPayment('p1'), isTrue);
    },
  );
}
