import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  group('WorkerStatus parsing', () {
    test(
      'defaults to active when the field is missing (backward compatible)',
      () {
        final worker = WorkerProfile.fromMap('w1', {
          'workspaceId': 'ws',
          'name': 'Sam',
        });
        expect(worker.status, WorkerStatus.active);
      },
    );

    test('parses the known status values', () {
      WorkerProfile parse(String value) =>
          WorkerProfile.fromMap('w', {'status': value});

      expect(parse('active').status, WorkerStatus.active);
      expect(parse('inactive').status, WorkerStatus.inactive);
      expect(parse('terminated').status, WorkerStatus.terminated);
    });

    test('falls back to active for unknown/empty status values', () {
      expect(
        WorkerProfile.fromMap('w', {'status': 'banana'}).status,
        WorkerStatus.active,
      );
      expect(
        WorkerProfile.fromMap('w', {'status': ''}).status,
        WorkerStatus.active,
      );
    });

    test('WorkerStatus.fromValue is null-safe', () {
      expect(WorkerStatus.fromValue(null), WorkerStatus.active);
      expect(WorkerStatus.fromValue('terminated'), WorkerStatus.terminated);
    });
  });

  group('status is independent of archive', () {
    test('a terminated worker can remain un-archived', () {
      final worker = WorkerProfile.fromMap('w', {
        'status': 'terminated',
        'isArchived': false,
      });
      expect(worker.status, WorkerStatus.terminated);
      expect(worker.isArchived, isFalse);
    });

    test('an archived worker can still be active', () {
      final worker = WorkerProfile.fromMap('w', {
        'status': 'active',
        'isArchived': true,
      });
      expect(worker.status, WorkerStatus.active);
      expect(worker.isArchived, isTrue);
    });
  });

  group('serialization and editing', () {
    test('toMap round-trips the status value', () {
      final worker = WorkerProfile.fromMap('w', {
        'workspaceId': 'ws',
        'name': 'Sam',
        'status': 'inactive',
      });
      final map = worker.toMap();
      expect(map['status'], 'inactive');
      expect(WorkerProfile.fromMap('w', map).status, WorkerStatus.inactive);
    });

    test('copyWith changes status while preserving other fields', () {
      final worker = WorkerProfile.fromMap('w', {
        'workspaceId': 'ws',
        'name': 'Sam',
        'dailyWage': 100,
        'status': 'active',
      });

      final edited = worker.copyWith(status: WorkerStatus.terminated);

      expect(edited.status, WorkerStatus.terminated);
      expect(edited.name, 'Sam');
      expect(edited.dailyWage, 100);
      expect(edited.workspaceId, 'ws');
    });
  });

  group('repository filters status independently of archive', () {
    late Directory tempDir;
    late Box<String> box;
    late OfflineActionQueue queue;
    late FakeFirebaseFirestore firestore;
    late FirebaseWorkerRepository repo;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('worker_status_test_');
      Hive.init(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    setUp(() async {
      box = await Hive.openBox<String>(
        'wq_${DateTime.now().microsecondsSinceEpoch}',
      );
      queue = OfflineActionQueue(box);
      firestore = FakeFirebaseFirestore();
      repo = FirebaseWorkerRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      Future<void> seed(String id, WorkerStatus status, bool archived) {
        return firestore.collection('workers').doc(id).set({
          'workspaceId': 'ws',
          'name': id,
          'status': status.value,
          'isArchived': archived,
          'createdAt': DateTime.utc(2026, 6, 1),
        });
      }

      await seed('active1', WorkerStatus.active, false);
      await seed('inactive1', WorkerStatus.inactive, false);
      await seed('terminated1', WorkerStatus.terminated, false);
      await seed('archivedActive', WorkerStatus.active, true);
    });

    tearDown(() async {
      await box.close();
    });

    test(
      'default returns every non-archived worker regardless of status',
      () async {
        final page = await repo.fetchWorkersPage('ws');
        final ids = page.items.map((w) => w.id).toSet();
        expect(ids, {'active1', 'inactive1', 'terminated1'});
        expect(ids, isNot(contains('archivedActive')));
      },
    );

    test('filters to the requested statuses only', () async {
      final page = await repo.fetchWorkersPage(
        'ws',
        statuses: {WorkerStatus.active},
      );
      expect(page.items.map((w) => w.id), ['active1']);
    });

    test('filters to multiple statuses', () async {
      final page = await repo.fetchWorkersPage(
        'ws',
        statuses: {WorkerStatus.inactive, WorkerStatus.terminated},
      );
      expect(page.items.map((w) => w.id).toSet(), {'inactive1', 'terminated1'});
    });

    test(
      'a terminated, non-archived worker is still visible by default',
      () async {
        final page = await repo.fetchWorkersPage('ws');
        final terminated = page.items.firstWhere((w) => w.id == 'terminated1');
        expect(terminated.status, WorkerStatus.terminated);
        expect(terminated.isArchived, isFalse);
      },
    );
  });

  group('repository persists worker status', () {
    test('passes selected status when creating a worker', () async {
      final mutationService = _MockWorkspaceMutationService();
      when(
        () => mutationService.createWorker(
          workspaceId: any(named: 'workspaceId'),
          name: any(named: 'name'),
          phoneNumber: any(named: 'phoneNumber'),
          dailyWage: any(named: 'dailyWage'),
          billingType: any(named: 'billingType'),
          workerType: any(named: 'workerType'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async => const MutationResult());
      final repo = FirebaseWorkerRepository(
        FakeFirebaseFirestore(),
        mutationService,
        OfflineActionQueue(await Hive.openBox<String>('status_create')),
      );

      await repo.createWorker(
        workspaceId: 'ws',
        userId: 'user_1',
        name: 'Sam',
        phoneNumber: '0100',
        dailyWage: 100,
        billingType: 'daily',
        status: WorkerStatus.inactive,
      );

      verify(
        () => mutationService.createWorker(
          workspaceId: 'ws',
          name: 'Sam',
          phoneNumber: '0100',
          dailyWage: 100,
          billingType: 'daily',
          workerType: any(named: 'workerType'),
          notes: any(named: 'notes'),
          status: 'inactive',
        ),
      ).called(1);
      await Hive.box<String>('status_create').close();
    });

    test('passes edited status when updating a worker', () async {
      final mutationService = _MockWorkspaceMutationService();
      when(
        () => mutationService.updateWorker(
          workspaceId: any(named: 'workspaceId'),
          workerId: any(named: 'workerId'),
          name: any(named: 'name'),
          phoneNumber: any(named: 'phoneNumber'),
          dailyWage: any(named: 'dailyWage'),
          billingType: any(named: 'billingType'),
          workerType: any(named: 'workerType'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async => const MutationResult());
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('workers').doc('w1').set({
        'workspaceId': 'ws',
        'name': 'Sam',
        'status': 'active',
      });
      final repo = FirebaseWorkerRepository(
        firestore,
        mutationService,
        OfflineActionQueue(await Hive.openBox<String>('status_update')),
      );

      await repo.updateWorker(
        workerId: 'w1',
        name: 'Sam',
        phoneNumber: '0100',
        dailyWage: 100,
        billingType: 'daily',
        status: WorkerStatus.terminated,
      );

      verify(
        () => mutationService.updateWorker(
          workspaceId: 'ws',
          workerId: 'w1',
          name: 'Sam',
          phoneNumber: '0100',
          dailyWage: 100,
          billingType: 'daily',
          workerType: any(named: 'workerType'),
          notes: any(named: 'notes'),
          status: 'terminated',
        ),
      ).called(1);
      await Hive.box<String>('status_update').close();
    });
  });
}
