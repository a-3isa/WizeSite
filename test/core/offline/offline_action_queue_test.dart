import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'offline_action_queue_contract_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_action_queue_contract_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('offline_action_queue_contract_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('enqueue records clientSavedAt for conflict resolution', () async {
    final savedAt = DateTime.utc(2026, 5, 27, 8, 30);

    final action = await queue.enqueue(
      type: 'update_expense',
      payload: {'expenseId': 'expense_1'},
      clientSavedAt: savedAt,
    );

    expect(
      action.payload[OfflineActionPayloadKeys.clientSavedAt],
      savedAt.toIso8601String(),
    );

    final restored = (await queue.list()).single;
    expect(
      restored.payload[OfflineActionPayloadKeys.clientSavedAt],
      savedAt.toIso8601String(),
    );
  });

  test(
    'serializes attachment upload payload with local retry metadata',
    () async {
      final action = await queue.enqueue(
        type: OfflineActionQueueTypes.attachmentUpload,
        payload: {
          OfflineActionPayloadKeys.workspaceId: 'workspace_1',
          OfflineActionPayloadKeys.ownerType: 'expense',
          OfflineActionPayloadKeys.ownerId: 'expense_1',
          OfflineActionPayloadKeys.attachment: {
            'id': 'attachment_1',
            'fileName': 'invoice.pdf',
            'localPath': r'C:\pending\invoice.pdf',
            'contentType': 'application/pdf',
            'size': 2048,
            'uploadStatus': 'pending',
          },
        },
      );

      expect(action.type, OfflineActionQueueTypes.attachmentUpload);
      expect(
        action.payload[OfflineActionPayloadKeys.attachment]['localPath'],
        r'C:\pending\invoice.pdf',
      );
      expect(
        (await queue.list()).single.payload[OfflineActionPayloadKeys
            .attachment]['uploadStatus'],
        'pending',
      );
    },
  );

  test('serializes entity upsert and summary delta action payloads', () async {
    await queue.enqueue(
      type: OfflineActionQueueTypes.entityUpsert,
      payload: {
        OfflineActionPayloadKeys.workspaceId: 'workspace_1',
        OfflineActionPayloadKeys.entity: {
          'id': 'entity_1',
          'name': 'Acme Materials',
          'type': 'supplier',
          'normalizedName': 'acme materials',
        },
      },
    );
    await queue.enqueue(
      type: OfflineActionQueueTypes.summaryDelta,
      payload: {
        OfflineActionPayloadKeys.workspaceId: 'workspace_1',
        OfflineActionPayloadKeys.summaryScope: 'weekly',
        OfflineActionPayloadKeys.summaryId: '2026-W22',
        OfflineActionPayloadKeys.summaryDelta: {
          'expenseTotal': 1500,
          'transactionCount': 1,
        },
      },
    );

    final actions = await queue.list();

    expect(actions.map((action) => action.type), [
      OfflineActionQueueTypes.entityUpsert,
      OfflineActionQueueTypes.summaryDelta,
    ]);
    expect(
      actions.first.payload[OfflineActionPayloadKeys.entity]['normalizedName'],
      'acme materials',
    );
    expect(
      actions.last.payload[OfflineActionPayloadKeys
          .summaryDelta]['expenseTotal'],
      1500,
    );
  });

  test(
    'preserves enqueue order when the clock returns the same timestamp',
    () async {
      final fixedNow = DateTime.utc(2026, 6, 15, 1, 0, 0);
      queue = OfflineActionQueue(box, now: () => fixedNow);

      await queue.enqueue(
        type: OfflineActionQueueTypes.entityUpsert,
        payload: {
          OfflineActionPayloadKeys.workspaceId: 'workspace_1',
          OfflineActionPayloadKeys.entity: {
            'id': 'entity_1',
            'name': 'First',
            'type': 'supplier',
          },
        },
      );
      await queue.enqueue(
        type: OfflineActionQueueTypes.summaryDelta,
        payload: {
          OfflineActionPayloadKeys.workspaceId: 'workspace_1',
          OfflineActionPayloadKeys.summaryScope: 'weekly',
          OfflineActionPayloadKeys.summaryId: '2026-W22',
          OfflineActionPayloadKeys.summaryDelta: {'expenseTotal': 25},
        },
      );

      final actions = await queue.list();

      expect(actions.map((action) => action.type), [
        OfflineActionQueueTypes.entityUpsert,
        OfflineActionQueueTypes.summaryDelta,
      ]);
      expect(actions.first.createdAt.isBefore(actions.last.createdAt), isTrue);
    },
  );

  test('parses legacy actions without resolution fields', () {
    final action = OfflineAction.fromMap({
      'id': 'legacy_1',
      'type': 'update_expense',
      'payload': {'expenseId': 'expense_1'},
      'createdAt': DateTime.utc(2026, 6, 15).toIso8601String(),
      'status': OfflineActionStatus.synced,
    });

    expect(action.resolutionType, isNull);
    expect(action.resolutionAt, isNull);
    expect(action.resolutionTargetId, isNull);
  });

  test(
    'serializes applied and skipped-newer-version resolution metadata',
    () async {
      final appliedAt = DateTime.now();
      final skippedAt = appliedAt.add(const Duration(milliseconds: 1));
      final applied = await queue.enqueue(
        type: 'update_expense',
        payload: {'expenseId': 'expense_1'},
      );
      final skipped = await queue.enqueue(
        type: 'update_expense',
        payload: {'expenseId': 'expense_1'},
      );

      await queue.save(
        applied.copyWith(
          status: OfflineActionStatus.synced,
          syncedAt: appliedAt,
          resolutionType: OfflineActionResolutionType.applied,
          resolutionAt: appliedAt,
          resolutionTargetId: 'expense_1',
        ),
      );
      await queue.save(
        skipped.copyWith(
          status: OfflineActionStatus.synced,
          syncedAt: skippedAt,
          resolutionType: OfflineActionResolutionType.skippedNewerVersion,
          resolutionAt: skippedAt,
          resolutionTargetId: 'expense_1',
        ),
      );

      final restored = await queue.list();

      expect(restored.map((action) => action.resolutionType), [
        OfflineActionResolutionType.applied,
        OfflineActionResolutionType.skippedNewerVersion,
      ]);
      expect(restored.first.resolutionAt, appliedAt);
      expect(restored.last.resolutionTargetId, 'expense_1');
    },
  );

  test(
    'retryAction resets one failed action without touching others',
    () async {
      final first = await queue.enqueue(type: 'update_expense', payload: {});
      final second = await queue.enqueue(type: 'update_payment', payload: {});
      final retryAt = DateTime.utc(2026, 6, 15, 12);
      await queue.save(
        first.copyWith(
          status: OfflineActionStatus.failed,
          retryCount: 2,
          lastError: 'Network unavailable',
          lastErrorCode: 'unavailable',
          nextAttemptAt: retryAt,
        ),
      );
      await queue.save(
        second.copyWith(
          status: OfflineActionStatus.failed,
          retryCount: 1,
          lastError: 'Permission denied',
          lastErrorCode: 'permission-denied',
          nextAttemptAt: retryAt,
        ),
      );

      final retried = await queue.retryAction(first.id);
      final actions = await queue.list();

      expect(retried.id, first.id);
      expect(retried.status, OfflineActionStatus.pending);
      expect(retried.retryCount, 0);
      expect(retried.lastError, isNull);
      expect(retried.lastErrorCode, isNull);
      expect(retried.nextAttemptAt, isNull);

      final untouched = actions.singleWhere((action) => action.id == second.id);
      expect(untouched.status, OfflineActionStatus.failed);
      expect(untouched.retryCount, 1);
      expect(untouched.lastErrorCode, 'permission-denied');
    },
  );
}
