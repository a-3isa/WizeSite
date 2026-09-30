import 'dart:convert';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/storage/hive_boxes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

class PendingAttachmentRecord {
  const PendingAttachmentRecord({
    required this.id,
    required this.workspaceId,
    required this.ownerType,
    required this.ownerId,
    required this.attachment,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String ownerType;
  final String ownerId;
  final Attachment attachment;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRetryable =>
      attachment.uploadStatus == AttachmentUploadStatus.pending ||
      attachment.uploadStatus == AttachmentUploadStatus.failed;

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspaceId': workspaceId,
    'ownerType': ownerType,
    'ownerId': ownerId,
    'attachment': attachment.toMap(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PendingAttachmentRecord.fromMap(Map<String, dynamic> map) {
    return PendingAttachmentRecord(
      id: map['id'] as String? ?? '',
      workspaceId: map['workspaceId'] as String? ?? '',
      ownerType: map['ownerType'] as String? ?? '',
      ownerId: map['ownerId'] as String? ?? '',
      attachment: Attachment.fromMap(
        Map<String, dynamic>.from(map['attachment'] as Map? ?? const {}),
      ),
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  PendingAttachmentRecord copyWith({
    Attachment? attachment,
    DateTime? updatedAt,
  }) {
    return PendingAttachmentRecord(
      id: id,
      workspaceId: workspaceId,
      ownerType: ownerType,
      ownerId: ownerId,
      attachment: attachment ?? this.attachment,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _parseDate(Object? raw) {
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.now();
  }
}

class PendingAttachmentService {
  const PendingAttachmentService(this._box);

  final Box<String> _box;

  static Future<PendingAttachmentService> open() async {
    final box = await openEncryptedBox<String>('pending_attachments');
    return PendingAttachmentService(box);
  }

  Future<PendingAttachmentRecord> savePending({
    required String workspaceId,
    required String ownerType,
    required String ownerId,
    required Attachment attachment,
  }) async {
    final now = DateTime.now();
    final record = PendingAttachmentRecord(
      id: _recordId(
        ownerType: ownerType,
        ownerId: ownerId,
        attachmentId: attachment.id,
      ),
      workspaceId: workspaceId,
      ownerType: ownerType,
      ownerId: ownerId,
      attachment: _attachmentWithStatus(
        attachment,
        status: AttachmentUploadStatus.pending,
      ),
      createdAt: now,
      updatedAt: now,
    );
    await _save(record);
    return record;
  }

  Future<List<PendingAttachmentRecord>> listForOwner({
    required String ownerType,
    required String ownerId,
  }) async {
    final records = await _allRecords();
    return records
        .where(
          (record) =>
              record.ownerType == ownerType && record.ownerId == ownerId,
        )
        .toList(growable: false);
  }

  Future<List<PendingAttachmentRecord>> listPending() async {
    final records = await _allRecords();
    return records
        .where((record) => record.isRetryable)
        .toList(growable: false);
  }

  Future<void> markUploading({required String id}) {
    return _updateAttachment(
      id: id,
      status: AttachmentUploadStatus.uploading,
      clearError: true,
    );
  }

  Future<void> markUploaded({
    required String id,
    required String storagePath,
    required String downloadUrl,
  }) {
    return _updateAttachment(
      id: id,
      status: AttachmentUploadStatus.uploaded,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      clearError: true,
    );
  }

  Future<void> markUploadedAndRemove({
    required String id,
    required String storagePath,
    required String downloadUrl,
  }) async {
    await markUploaded(
      id: id,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
    );
    await remove(id);
  }

  Future<void> markFailed({required String id, required String message}) {
    return _updateAttachment(
      id: id,
      status: AttachmentUploadStatus.failed,
      errorMessage: message,
    );
  }

  Future<void> markMissingLocalFile({required String id}) {
    return _updateAttachment(
      id: id,
      status: AttachmentUploadStatus.missingLocalFile,
      errorMessage: 'Attachment local file was not found.',
    );
  }

  Future<void> remove(String id) => _box.delete(id);

  Future<List<PendingAttachmentRecord>> _allRecords() async {
    final records =
        _box.values
            .map(
              (raw) => PendingAttachmentRecord.fromMap(
                jsonDecode(raw) as Map<String, dynamic>,
              ),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return records;
  }

  Future<void> _save(PendingAttachmentRecord record) {
    return _box.put(record.id, jsonEncode(record.toMap()));
  }

  Future<void> _updateAttachment({
    required String id,
    required AttachmentUploadStatus status,
    String? storagePath,
    String? downloadUrl,
    String? errorMessage,
    bool clearError = false,
  }) async {
    final raw = _box.get(id);
    if (raw == null) {
      return;
    }
    final record = PendingAttachmentRecord.fromMap(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    await _save(
      record.copyWith(
        attachment: _attachmentWithStatus(
          record.attachment,
          status: status,
          storagePath: storagePath,
          downloadUrl: downloadUrl,
          errorMessage: clearError ? null : errorMessage,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  static String _recordId({
    required String ownerType,
    required String ownerId,
    required String attachmentId,
  }) {
    return '$ownerType:$ownerId:$attachmentId';
  }

  static Attachment _attachmentWithStatus(
    Attachment attachment, {
    required AttachmentUploadStatus status,
    String? storagePath,
    String? downloadUrl,
    String? errorMessage,
  }) {
    return Attachment(
      id: attachment.id,
      fileName: attachment.fileName,
      storagePath: storagePath ?? attachment.storagePath,
      contentType: attachment.contentType,
      uploadedAt: attachment.uploadedAt,
      downloadUrl: downloadUrl ?? attachment.downloadUrl,
      type: attachment.type,
      size: attachment.size,
      uploadedBy: attachment.uploadedBy,
      localPath: attachment.localPath,
      uploadStatus: status,
      errorMessage: errorMessage,
    );
  }
}

final pendingAttachmentServiceProvider =
    FutureProvider<PendingAttachmentService>((ref) {
      return PendingAttachmentService.open();
    });
