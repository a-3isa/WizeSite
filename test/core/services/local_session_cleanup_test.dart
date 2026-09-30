import 'dart:io';

import 'package:buildtrack_app/core/services/local_session_cleanup.dart';
import 'package:buildtrack_app/core/storage/hive_boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_cleanup_test_');
    Hive.init(tempDir.path);
    hiveEncryptionCipher = null;
    hiveNeedsPlaintextMigration = false;
    hiveMarkedEncryptedBoxes.clear();
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sign-out cleanup empties queued Hive boxes', () async {
    final actions = await Hive.openBox<String>('offline_actions');
    final attachments = await Hive.openBox<String>('pending_attachments');
    await actions.put('action_1', '{"type":"create_expense"}');
    await attachments.put('att_1', '{"localPath":"/tmp/a.jpg"}');

    await LocalSessionCleanup.clearQueuedUserData();

    expect(actions.isEmpty, isTrue);
    expect(attachments.isEmpty, isTrue);
  });

  test('sign-out cleanup never opens a box itself', () async {
    // main() opens both queue boxes at startup, so a closed box means Hive was
    // never set up (early auth failure, widget tests). Opening one then leaves
    // an unhandled error on Hive's internal opening future.
    await LocalSessionCleanup.clearQueuedUserData();

    expect(Hive.isBoxOpen('offline_actions'), isFalse);
    expect(Hive.isBoxOpen('pending_attachments'), isFalse);
  });
}
