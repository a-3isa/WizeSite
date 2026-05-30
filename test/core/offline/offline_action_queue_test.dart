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
}
