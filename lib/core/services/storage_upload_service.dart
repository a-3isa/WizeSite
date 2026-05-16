import 'dart:io';
import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _extensionOf(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0) {
    return '';
  }
  return path.substring(dotIndex).toLowerCase();
}

String _contentTypeForAudioExtension(String extension) {
  switch (extension) {
    case '.wav':
      return 'audio/wav';
    case '.mp3':
      return 'audio/mpeg';
    case '.aac':
      return 'audio/aac';
    case '.webm':
      return 'audio/webm';
    case '.m4a':
    case '.mp4':
      return 'audio/mp4';
    default:
      return 'application/octet-stream';
  }
}

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
    final extension = _extensionOf(localFilePath).isEmpty
        ? '.m4a'
        : _extensionOf(localFilePath);
    final storagePath = 'voice-expenses/$userId/$timestamp$extension';
    final ref = _storage.ref(storagePath);
    final bytes = await source.readAsBytes();
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(
        contentType: _contentTypeForAudioExtension(extension),
        customMetadata: <String, String>{'uploadedBy': userId},
      ),
    );
    StreamSubscription<TaskSnapshot>? progressSubscription;

    if (onProgress != null) {
      progressSubscription = uploadTask.snapshotEvents.listen(
        (snapshot) {
          final total = snapshot.totalBytes;
          if (total <= 0) {
            return;
          }
          onProgress(snapshot.bytesTransferred / total);
        },
        onError: (_) {
          // Upload failures are handled by awaiting `uploadTask` below.
        },
      );
    }

    try {
      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();
      return UploadedVoiceFile(
        storagePath: storagePath,
        downloadUrl: downloadUrl,
      );
    } on FirebaseException catch (e) {
      throw StorageUploadException(_toUserMessage(e));
    } finally {
      await progressSubscription?.cancel();
    }
  }

  String _toUserMessage(FirebaseException error) {
    switch (error.code) {
      case 'unauthorized':
        return 'Upload is not authorized. Please sign in again and retry.';
      case 'canceled':
        return 'Upload was canceled. Please try again.';
      case 'quota-exceeded':
        return 'Storage quota was exceeded. Please try again later.';
      case 'retry-limit-exceeded':
        return 'Upload timed out. Please check your connection and retry.';
      case 'object-not-found':
        return 'Upload could not be completed in storage. Please try again.';
      default:
        return error.message ?? 'Failed to upload audio to Firebase Storage.';
    }
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
