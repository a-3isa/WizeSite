import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

const hiveAesKeyStorageKey = 'hive_aes_key_v1';
const hiveEncryptedFlagKey = 'hive_boxes_encrypted_v1';

HiveCipher? hiveEncryptionCipher;

/// Box names already copied into an AES Hive file this process (and persisted
/// when secure storage is available). Prevents a crash between migrate and
/// [persistHiveEncryptionReady] from re-opening ciphertext as plaintext.
final hiveMarkedEncryptedBoxes = <String>{};

/// Test seam for per-box encryption flags. When non-null, reads/writes skip
/// FlutterSecureStorage so tests can simulate a process restart.
Map<String, String>? hiveBoxEncryptFlagStore;

/// When true, existing on-disk boxes are copied into a new AES box before
/// encrypted open. Hive does not throw if a plaintext box is opened with a
/// cipher — it "recovers" an empty box — so this flag is required.
bool hiveNeedsPlaintextMigration = false;

FlutterSecureStorage defaultHiveKeyStore() => const FlutterSecureStorage();

Future<HiveAesCipher> loadOrCreateHiveCipher({
  FlutterSecureStorage? storage,
}) async {
  final secure = storage ?? defaultHiveKeyStore();
  final existing = await secure.read(key: hiveAesKeyStorageKey);
  final migrated = await secure.read(key: hiveEncryptedFlagKey);
  hiveNeedsPlaintextMigration = migrated != '1';

  if (existing != null && existing.isNotEmpty) {
    return HiveAesCipher(base64Decode(existing));
  }
  final bytes = Uint8List.fromList(Hive.generateSecureKey());
  await secure.write(key: hiveAesKeyStorageKey, value: base64Encode(bytes));
  return HiveAesCipher(bytes);
}

Future<void> persistHiveEncryptionReady({FlutterSecureStorage? storage}) async {
  final secure = storage ?? defaultHiveKeyStore();
  await secure.write(key: hiveEncryptedFlagKey, value: '1');
  hiveMarkedEncryptedBoxes.addAll([
    'app_prefs',
    'offline_actions',
    'pending_attachments',
  ]);
}

Future<Box<T>> openEncryptedBox<T>(String name, {HiveCipher? cipher}) async {
  if (Hive.isBoxOpen(name)) {
    return Hive.box<T>(name);
  }
  final encryptionCipher = cipher ?? hiveEncryptionCipher;
  if (encryptionCipher == null) {
    return Hive.openBox<T>(name);
  }
  if (hiveNeedsPlaintextMigration && await Hive.boxExists(name)) {
    if (hiveMarkedEncryptedBoxes.contains(name)) {
      return Hive.openBox<T>(name, encryptionCipher: encryptionCipher);
    }
    final flagged = await _readBoxEncryptedFlag(name);
    if (flagged == '1') {
      hiveMarkedEncryptedBoxes.add(name);
      return Hive.openBox<T>(name, encryptionCipher: encryptionCipher);
    }
    final migrated = await _migrateUnencryptedBox<T>(name, encryptionCipher);
    hiveMarkedEncryptedBoxes.add(name);
    await _writeBoxEncryptedFlag(name);
    return migrated;
  }
  hiveMarkedEncryptedBoxes.add(name);
  return Hive.openBox<T>(name, encryptionCipher: encryptionCipher);
}

String _boxEncryptedFlagKey(String name) => 'hive_box_encrypted_$name';

Future<String?> _readBoxEncryptedFlag(String name) async {
  final key = _boxEncryptedFlagKey(name);
  final store = hiveBoxEncryptFlagStore;
  if (store != null) {
    return store[key];
  }
  try {
    return await defaultHiveKeyStore().read(key: key);
  } catch (_) {
    return null;
  }
}

Future<void> _writeBoxEncryptedFlag(String name) async {
  final key = _boxEncryptedFlagKey(name);
  final store = hiveBoxEncryptFlagStore;
  if (store != null) {
    store[key] = '1';
    return;
  }
  try {
    await defaultHiveKeyStore().write(key: key, value: '1');
  } catch (_) {}
}

Future<Box<T>> _migrateUnencryptedBox<T>(String name, HiveCipher cipher) async {
  final plain = await Hive.openBox<T>(name);
  final entries = Map<dynamic, T>.from(plain.toMap());
  await plain.close();
  await Hive.deleteBoxFromDisk(name);
  final encrypted = await Hive.openBox<T>(name, encryptionCipher: cipher);
  if (entries.isNotEmpty) {
    await encrypted.putAll(entries);
  }
  return encrypted;
}
