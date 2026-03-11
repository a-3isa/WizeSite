import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadedVoiceFile {
  const UploadedVoiceFile({
    required this.storagePath,
    required this.downloadUrl,
  });

  final String storagePath;
  final String downloadUrl;
}

class StorageUploadService {
  const StorageUploadService(this._storage);

  final FirebaseStorage _storage;

  Future<UploadedVoiceFile> uploadVoiceExpenseAudio({
    required String userId,
    required String localFilePath,
    void Function(double progress)? onProgress,
  }) async {
    final source = File(localFilePath);
    final exists = await source.exists();
    if (!exists) {
      throw const StorageUploadException('Recorded audio file not found.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'voice-expenses/$userId/$timestamp.m4a';
    final ref = _storage.ref(storagePath);
    final uploadTask = ref.putFile(
      source,
      SettableMetadata(
        contentType: 'audio/mp4',
        customMetadata: <String, String>{'uploadedBy': userId},
      ),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0) {
          return;
        }
        onProgress(snapshot.bytesTransferred / total);
      });
    }

    try {
      await uploadTask;
    } on FirebaseException catch (e) {
      throw StorageUploadException(
        e.message ?? 'Failed to upload audio to Firebase Storage.',
      );
    }

    final downloadUrl = await ref.getDownloadURL();
    return UploadedVoiceFile(
      storagePath: storagePath,
      downloadUrl: downloadUrl,
    );
  }
}

class StorageUploadException implements Exception {
  const StorageUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

final storageUploadServiceProvider = Provider<StorageUploadService>((ref) {
  return StorageUploadService(FirebaseStorage.instance);
});
