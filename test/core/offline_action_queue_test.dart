import 'dart:async';
import 'dart:io';

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
}
