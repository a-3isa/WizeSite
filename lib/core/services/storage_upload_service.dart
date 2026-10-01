import 'dart:io';
import 'dart:typed_data';

import 'package:buildtrack_app/core/services/attachment_file_types.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

/// Uploads to the self-hosted file API, `POST /v1/files` (spec 004). Files are
/// read later through `getAttachmentDownloadUrl`, so no download URL is
/// returned (empty string).
class StorageUploadService {
  const StorageUploadService(this._transport);

  final SelfHostedRpcTransport _transport;

  Future<({String storagePath, int size})> _upload({
    required String kind,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String idempotencyKey,
  }) async {
    try {
      final result = await _transport.uploadFile(
        kind: kind,
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        idempotencyKey: idempotencyKey,
      );
      return (
        storagePath: '${result['storagePath']}',
        size: (result['sizeBytes'] as num?)?.toInt() ?? bytes.length,
      );
    } on CallableClientException catch (error) {
      final code = error.code ?? 'upload-failed';
      throw StorageUploadException(
        error.message,
        code: code,
        retryable: !const {
          'invalid-argument',
          'permission-denied',
          'unauthenticated',
        }.contains(code),
      );
    }
  }

  static String contentTypeForAttachmentPath(String path) {
    return AttachmentFileTypes.contentTypeForPath(path) ??
        'application/octet-stream';
  }

  Future<UploadedVoiceFile> uploadVoiceExpenseAudio({
    required String userId,
    required String localFilePath,
    void Function(double progress)? onProgress,
    String? idempotencyKey,
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
    final bytes = await source.readAsBytes();
    final uploaded = await _upload(
      kind: 'voice-expenses',
      bytes: bytes,
      fileName: '$timestamp$extension',
      contentType: _contentTypeForAudioExtension(extension),
      idempotencyKey: idempotencyKey ?? const Uuid().v4(),
    );
    onProgress?.call(1);
    return UploadedVoiceFile(
      storagePath: uploaded.storagePath,
      downloadUrl: '',
    );
  }

  Future<UploadedAttachment> uploadAttachment({
    required String userId,
    required String localFilePath,
    String? fileName,
    void Function(double progress)? onProgress,
    String? idempotencyKey,
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

    final resolvedName = fileName ?? source.uri.pathSegments.last;
    final bytes = await source.readAsBytes();
    final contentType = contentTypeForAttachmentPath(localFilePath);
    final uploaded = await _upload(
      kind: 'attachments',
      bytes: bytes,
      fileName: resolvedName,
      contentType: contentType,
      idempotencyKey: idempotencyKey ?? const Uuid().v4(),
    );
    onProgress?.call(1);
    return UploadedAttachment(
      storagePath: uploaded.storagePath,
      downloadUrl: '',
      fileName: resolvedName,
      contentType: contentType,
      size: uploaded.size,
    );
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

  @override
  String toString() => message;
}

final storageUploadServiceProvider = Provider<StorageUploadService>((ref) {
  return StorageUploadService(ref.watch(selfHostedRpcTransportProvider));
});
