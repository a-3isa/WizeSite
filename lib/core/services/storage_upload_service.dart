import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:buildtrack_app/core/services/attachment_file_types.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
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

class UploadedAttachment {
  const UploadedAttachment({
    required this.storagePath,
    required this.downloadUrl,
    required this.fileName,
    required this.contentType,
    required this.size,
  });

  final String storagePath;
  final String downloadUrl;
  final String fileName;
  final String contentType;
  final int size;
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

  static String contentTypeForAttachmentPath(String path) {
    return AttachmentFileTypes.contentTypeForPath(path) ??
        'application/octet-stream';
  }

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
      throw StorageUploadException.fromFirebase(e);
    } finally {
      await progressSubscription?.cancel();
    }
  }

  Future<UploadedAttachment> uploadAttachment({
    required String userId,
    required String localFilePath,
    String? fileName,
    void Function(double progress)? onProgress,
  }) async {
    final validationError = await AttachmentValidationService.validateLocalFile(
      localFilePath,
    );
    if (validationError != null) {
      throw StorageUploadException(
        validationError,
        code: 'invalid-attachment',
        retryable: false,
      );
    }

    final source = File(localFilePath);
    final exists = await source.exists();
    if (!exists) {
      throw const StorageUploadException(
        'Attachment file not found.',
        code: 'missing-local-file',
        retryable: false,
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = _extensionOf(localFilePath).isEmpty
        ? ''
        : _extensionOf(localFilePath);
    final resolvedName = fileName ?? source.uri.pathSegments.last;
    final storagePath = 'attachments/$userId/$timestamp$extension';
    final ref = _storage.ref(storagePath);
    final bytes = await source.readAsBytes();
    final contentType = contentTypeForAttachmentPath(localFilePath);
    final uploadTask = ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: <String, String>{'uploadedBy': userId},
      ),
    );
    StreamSubscription<TaskSnapshot>? progressSubscription;

    if (onProgress != null) {
      progressSubscription = uploadTask.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0) {
          return;
        }
        onProgress(snapshot.bytesTransferred / total);
      }, onError: (_) {});
    }

    try {
      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();
      return UploadedAttachment(
        storagePath: storagePath,
        downloadUrl: downloadUrl,
        fileName: resolvedName,
        contentType: contentType,
        size: bytes.length,
      );
    } on FirebaseException catch (e) {
      throw StorageUploadException.fromFirebase(e);
    } finally {
      await progressSubscription?.cancel();
    }
  }

  Future<String> getDownloadUrl(String storagePath) async {
    return _storage.ref(storagePath).getDownloadURL();
  }

  Future<Uint8List?> downloadAttachmentBytes(
    String storagePath, {
    int maxBytes = 20 * 1024 * 1024,
  }) async {
    final ref = _storage.ref(storagePath);
    return ref.getData(maxBytes);
  }
}

class StorageUploadException implements Exception {
  const StorageUploadException(
    this.message, {
    this.code = 'upload-failed',
    this.retryable = true,
  });

  final String message;
  final String code;
  final bool retryable;

  factory StorageUploadException.fromFirebase(FirebaseException error) {
    switch (error.code) {
      case 'unauthorized':
        return const StorageUploadException(
          'Upload is not authorized. Please sign in again and retry.',
          code: 'unauthorized',
          retryable: false,
        );
      case 'canceled':
        return const StorageUploadException(
          'Upload was canceled. Please try again.',
          code: 'canceled',
        );
      case 'quota-exceeded':
        return const StorageUploadException(
          'Storage quota was exceeded. Please try again later.',
          code: 'quota-exceeded',
        );
      case 'retry-limit-exceeded':
        return const StorageUploadException(
          'Upload timed out. Please check your connection and retry.',
          code: 'retry-limit-exceeded',
        );
      case 'object-not-found':
        return const StorageUploadException(
          'Upload could not be completed in storage. Please try again.',
          code: 'object-not-found',
        );
      default:
        return StorageUploadException(
          error.message ?? 'Failed to upload audio to Firebase Storage.',
          code: error.code,
        );
    }
  }

  @override
  String toString() => message;
}

final storageUploadServiceProvider = Provider<StorageUploadService>((ref) {
  return StorageUploadService(FirebaseStorage.instance);
});
