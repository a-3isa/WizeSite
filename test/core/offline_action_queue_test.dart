import 'dart:async';
import 'dart:io';

import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_queue_test_');
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

  test(
    'drain processes actions enqueued while drain is already active',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final processed = <String>[];

      Future<void> handler(OfflineAction action) async {
        processed.add(action.type);
        if (action.type == 'first' && !firstStarted.isCompleted) {
          firstStarted.complete();
          await releaseFirst.future;
        }
      }

      await queue.enqueue(type: 'first', payload: {'value': 1});
      final firstDrain = queue.drain(handler);

      await firstStarted.future;

      await queue.enqueue(type: 'second', payload: {'value': 2});
      final secondDrain = queue.drain(handler);

      releaseFirst.complete();

      await Future.wait([firstDrain, secondDrain]);

      expect(await queue.pendingCount(), 0);
      expect(processed, containsAllInOrder(['first', 'second']));
    },
  );

  test('enqueue adds stable client mutation metadata to payload', () async {
    final action = await queue.enqueue(type: 'expense', payload: {'value': 1});

    expect(action.id, isNotEmpty);
    expect(action.payload['clientMutationId'], action.id);
    expect(action.payload['clientCreatedAt'], isNotEmpty);
    expect(action.payload['clientUpdatedAt'], isNotEmpty);
  });

  test(
    'successful drain keeps recently synced actions visible but not pending',
    () async {
      final action = await queue.enqueue(
        type: 'payment',
        payload: {'value': 1},
      );

      await queue.drain((_) async {});

      expect(await queue.pendingCount(), 0);
      final visibleActions = await queue.list();
      expect(visibleActions, hasLength(1));
      expect(visibleActions.first.id, action.id);
      expect(visibleActions.first.status, OfflineActionStatus.synced);
      expect(visibleActions.first.syncedAt, isNotNull);
    },
  );

  test(
    'drain reloads remapped child payloads in the same pass',
    () async {
      final project = await queue.enqueue(
        type: 'create_project',
        payload: {'name': 'Site A'},
      );
      final expense = await queue.enqueue(
        type: 'create_expense',
        payload: {
          'projectId': 'pending_${project.id}',
          'amount': 40,
        },
      );

      final seenProjectIds = <String>[];
      await queue.drain((action) async {
        if (action.type == 'create_project') {
          await queue.remapPendingProjectIds(
            pendingId: 'pending_${action.id}',
            serverId: 'project_server',
          );
          return;
        }
        seenProjectIds.add('${action.payload['projectId']}');
      });

      expect(seenProjectIds, ['project_server']);
      final stored = await queue.list(includeExpiredSynced: true);
      final storedExpense = stored.firstWhere((item) => item.id == expense.id);
      expect(storedExpense.payload['projectId'], 'project_server');
    },
  );

  test('delete project actions are normal optimistic queue entries', () async {
    final action = await queue.enqueue(
      type: 'delete_project',
      payload: {'workspaceId': 'workspace_1', 'projectId': 'project_1'},
    );

    expect(action.type, 'delete_project');
    expect(action.payload['clientMutationId'], action.id);
    expect(await queue.pendingCount(), 1);
  });

  test(
    'terminal callable failures are stored as dead letters with code',
    () async {
      await queue.enqueue(type: 'payment', payload: {'value': 1});

      await queue.drain((_) async {
        throw const CallableClientException(
          'Project is archived and can no longer accept payments.',
          code: 'permission-denied',
        );
      });

      final deadLetters = await queue.deadLetters();
      expect(deadLetters, hasLength(1));
      expect(deadLetters.first.status, OfflineActionStatus.deadLetter);
      expect(deadLetters.first.lastErrorCode, 'permission-denied');
      expect(deadLetters.first.lastError, contains('archived'));
    },
  );

  test(
    'drain stops when the earliest unsynced action is still in backoff',
    () async {
      final first = await queue.enqueue(
        type: 'create_project',
        payload: {'name': 'Site A'},
      );
      await queue.enqueue(type: 'create_expense', payload: {'amount': 40});
      await queue.save(
        first.copyWith(
          status: OfflineActionStatus.failed,
          nextAttemptAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      final processed = <String>[];
      await queue.drain((action) async {
        processed.add(action.type);
      });

      expect(processed, isEmpty);
      expect(await queue.pendingCount(), 2);
    },
  );
}
