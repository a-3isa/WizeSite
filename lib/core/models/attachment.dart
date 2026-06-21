import 'package:cloud_firestore/cloud_firestore.dart';

enum AttachmentUploadStatus {
  pending('pending'),
  uploading('uploading'),
  uploaded('uploaded'),
  failed('failed'),
  missingLocalFile('missingLocalFile');

  const AttachmentUploadStatus(this.value);

  final String value;

  static AttachmentUploadStatus fromValue(Object? raw) {
    final value = raw as String?;
    if (value == null || value.isEmpty) {
      return AttachmentUploadStatus.uploaded;
    }
    return AttachmentUploadStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => AttachmentUploadStatus.uploaded,
    );
  }
}

class Attachment {
  const Attachment({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.contentType,
    required this.uploadedAt,
    this.downloadUrl,
    this.type,
    this.size,
    this.uploadedBy,
    this.localPath,
    this.uploadStatus = AttachmentUploadStatus.uploaded,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final String storagePath;
  final String contentType;
  final DateTime uploadedAt;
  final String? downloadUrl;
  final String? type;
  final int? size;
  final String? uploadedBy;
  final String? localPath;
  final AttachmentUploadStatus uploadStatus;
  final String? errorMessage;

  factory Attachment.fromMap(Map<String, dynamic> map) {
    return Attachment(
      id: map['id'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      storagePath: map['storagePath'] as String? ?? '',
      contentType: map['contentType'] as String? ?? 'application/octet-stream',
      uploadedAt: _parseUploadedAt(map['uploadedAt']),
      downloadUrl: (map['downloadUrl'] as String?)?.isNotEmpty == true
          ? map['downloadUrl'] as String?
          : (map['url'] as String?),
      type: map['type'] as String?,
      size: (map['size'] as num?)?.toInt(),
      uploadedBy: map['uploadedBy'] as String?,
      localPath: (map['localPath'] as String?)?.isNotEmpty == true
          ? map['localPath'] as String?
          : null,
      uploadStatus: AttachmentUploadStatus.fromValue(map['uploadStatus']),
      errorMessage: (map['errorMessage'] as String?)?.isNotEmpty == true
          ? map['errorMessage'] as String?
          : null,
    );
  }

  static DateTime _parseUploadedAt(Object? raw) {
    if (raw is DateTime) {
      return raw;
    }
    if (raw is Timestamp) {
      return raw.toDate();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.now();
  }

  static List<Attachment> listFromDynamic(Object? raw) {
    if (raw is! Iterable) {
      return const <Attachment>[];
    }
    return raw
        .map((item) {
          if (item is Map<String, dynamic>) {
            return item;
          }
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .map(Attachment.fromMap)
        .toList(growable: false);
  }

  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{
      'id': id,
      'fileName': fileName,
      'storagePath': storagePath,
      'contentType': contentType,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
    if (downloadUrl != null && downloadUrl!.isNotEmpty) {
      result['downloadUrl'] = downloadUrl;
      result['url'] = downloadUrl;
    }
    if (type != null && type!.isNotEmpty) {
      result['type'] = type;
    }
    if (size != null) {
      result['size'] = size;
    }
    if (uploadedBy != null && uploadedBy!.isNotEmpty) {
      result['uploadedBy'] = uploadedBy;
    }
    if (localPath != null && localPath!.isNotEmpty) {
      result['localPath'] = localPath;
    }
    result['uploadStatus'] = uploadStatus.value;
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      result['errorMessage'] = errorMessage;
    }
    return result;
  }

  bool get isPdf {
    return contentType == 'application/pdf' ||
        fileName.toLowerCase().endsWith('.pdf');
  }
}
