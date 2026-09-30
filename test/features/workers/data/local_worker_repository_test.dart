import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
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
  late LocalWorkerRepository workers;
  late LocalWorkerEntryRepository entries;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_workers_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_local_workers');
    queue = OfflineActionQueue(box);
    local = await LocalTestDb.open();
    final firestore = FakeFirebaseFirestore();
    workers = LocalWorkerRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
      Future.value(local.db),
    );
    entries = LocalWorkerEntryRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
      Future.value(local.db),
    );
    await local.seedRows('workers', [
      {
        'id': 'w1',
        'workspace_id': 'ws_1',
        'name': 'علي',
        'status': 'active',
        'daily_wage': 75.0,
        'is_archived': 0,
        'created_at': '2026-05-01 00:00:00Z',
      },
      {
        'id': 'w2',
        'workspace_id': 'ws_1',
        'name': 'Omar',
        'status': 'inactive',
        'is_archived': 0,
        'created_at': '2026-06-01 00:00:00Z',
      },
      {
        'id': 'w_arch',
        'workspace_id': 'ws_1',
        'name': 'Gone',
        'is_archived': 1,
        'created_at': '2026-07-01 00:00:00Z',
      },
    ]);
    await local.seedRows('worker_entries', [
      {
        'id': 'we1',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'worker_id': 'w1',
        'days_worked': 2.0,
        'daily_wage': 75.0,
        'date': '2026-06-04 00:00:00Z',
        'is_archived': 0,
        'attachments': '[]',
      },
      {
        'id': 'we2',
        'workspace_id': 'ws_1',
        'project_id': 'p1',
        'worker_id': 'w1',
        'days_worked': 1.0,
        'daily_wage': 75.0,
        'date': '2026-06-10 00:00:00Z',
        'is_archived': 0,
        'attachments': '[]',
      },
    ]);
  });

  tearDown(() async {
    await local.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_local_workers');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'watchWorkers: active (non-archived), deterministic order, status filter',
    () async {
      final all = await workers.watchWorkers('ws_1').first;
      expect(all.map((w) => w.id), ['w2', 'w1']);
      expect(all.last.name, 'علي');
      final active = await workers
          .watchWorkers('ws_1', statuses: {WorkerStatus.active})
          .first;
      expect(active.map((w) => w.id), ['w1']);
    },
  );

  test('fetchWorkersPage keyset and getWorker', () async {
    final first = await workers.fetchWorkersPage('ws_1', pageSize: 1);
    expect(first.items.map((w) => w.id), ['w2']);
    final second = await workers.fetchWorkersPage(
      'ws_1',
      pageSize: 1,
      cursor: first.nextCursor,
    );
    expect(second.items.map((w) => w.id), ['w1']);
    expect((await workers.getWorker('w1'))?.name, 'علي');
  });

  test('watchEntriesByWorker newest first; getEntry', () async {
    final list = await entries
        .watchEntriesByWorker(workspaceId: 'ws_1', workerId: 'w1')
        .first;
    expect(list.map((e) => e.id), ['we2', 'we1']);
    expect((await entries.getEntry('we1'))?.id, 'we1');
    expect(await entries.getEntry('missing'), isNull);
  });
}
