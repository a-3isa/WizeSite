import 'dart:io';
import 'dart:typed_data';

import 'package:buildtrack_app/core/storage/hive_boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late HiveAesCipher cipher;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_boxes_test_');
    Hive.init(tempDir.path);
    cipher = HiveAesCipher(Uint8List.fromList(List<int>.filled(32, 7)));
  });

  tearDown(() async {
    hiveEncryptionCipher = null;
    hiveNeedsPlaintextMigration = false;
    hiveMarkedEncryptedBoxes.clear();
    hiveBoxEncryptFlagStore = null;
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('openEncryptedBox migrates an existing plaintext box', () async {
    hiveNeedsPlaintextMigration = true;
    final plain = await Hive.openBox<String>('prefs_migrate');
    await plain.put('locale', 'ar');
    await plain.close();

    final encrypted = await openEncryptedBox<String>(
      'prefs_migrate',
      cipher: cipher,
    );
    expect(encrypted.get('locale'), 'ar');
    await encrypted.close();

    hiveNeedsPlaintextMigration = false;
    final reopened = await Hive.openBox<String>(
      'prefs_migrate',
      encryptionCipher: cipher,
    );
    expect(reopened.get('locale'), 'ar');
    await reopened.close();
  });

  test('per-box encrypt flag survives without global persist', () async {
    hiveBoxEncryptFlagStore = {};
    hiveNeedsPlaintextMigration = true;
    final plain = await Hive.openBox<String>('prefs_flag');
    await plain.put('locale', 'ar');
    await plain.close();

    final first = await openEncryptedBox<String>(
      'prefs_flag',
      cipher: cipher,
    );
    expect(first.get('locale'), 'ar');
    await first.close();

    hiveMarkedEncryptedBoxes.clear();
    hiveNeedsPlaintextMigration = true;
    final second = await openEncryptedBox<String>(
      'prefs_flag',
      cipher: cipher,
    );
    expect(second.get('locale'), 'ar');
    await second.close();
  });

  test('migrated boxes are not re-opened as plaintext in the same process', () async {
    hiveNeedsPlaintextMigration = true;
    final plain = await Hive.openBox<String>('prefs_remigrate');
    await plain.put('locale', 'ar');
    await plain.close();

    final first = await openEncryptedBox<String>(
      'prefs_remigrate',
      cipher: cipher,
    );
    expect(first.get('locale'), 'ar');
    await first.close();

    hiveNeedsPlaintextMigration = true;
    final second = await openEncryptedBox<String>(
      'prefs_remigrate',
      cipher: cipher,
    );
    expect(second.get('locale'), 'ar');
    await second.close();
  });

  test('openEncryptedBox without a cipher stays compatible with tests', () async {
    final box = await openEncryptedBox<String>('prefs_encrypted');
    await box.put('theme', 'dark');
    expect(box.get('theme'), 'dark');
    await box.close();
  });
}
