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
      'offline_attachment_queue_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_attachment_actions_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('offline_attachment_actions_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'offline queue preserves attachment metadata for pending actions',
    () async {
      final attachment = {
        'id': 'attach_1',
        'fileName': 'receipt.pdf',
        'storagePath': 'attachments/receipt.pdf',
        'contentType': 'application/pdf',
        'downloadUrl': 'https://example.com/receipt.pdf',
        'uploadedAt': DateTime.utc(2026, 5, 25).toIso8601String(),
        'size': 1024,
      };

      final action = await queue.enqueue(
        type: 'createExpense',
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'attachments': [attachment],
        },
      );

      expect(action.payload['attachments'], isA<List<Object?>>());
      expect(
        (action.payload['attachments'] as List<Object?>).first,
        containsPair('downloadUrl', attachment['downloadUrl']),
      );

      await queue.drain((pendingAction) async {
        expect(pendingAction.payload['attachments'], isA<List<Object?>>());
        expect(
          (pendingAction.payload['attachments'] as List<Object?>).first,
          containsPair('id', 'attach_1'),
        );
      });

      final list = await queue.list();
      expect(list, hasLength(1));
      expect(list.first.status, OfflineActionStatus.synced);
      expect(list.first.payload['attachments'], isA<List<Object?>>());
      expect(
        (list.first.payload['attachments'] as List<Object?>).first,
        containsPair('fileName', 'receipt.pdf'),
      );
    },
  );
}
