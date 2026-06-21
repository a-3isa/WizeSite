import 'package:buildtrack_app/core/models/attachment.dart';

class AppEntity {
  const AppEntity({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.normalizedName,
    required this.type,
    required this.createdAt,
    this.attachments = const [],
    this.lastUsedAt,
    this.clientMutationId = '',
  });

  final String id;
  final String workspaceId;
  final String name;
  final String normalizedName;
  final String type;
  final DateTime createdAt;
  final List<Attachment> attachments;
  final DateTime? lastUsedAt;
  final String clientMutationId;

  factory AppEntity.fromMap(String id, Map<String, dynamic> map) {
    final name = '${map['name'] ?? ''}'.trim();
    return AppEntity(
      id: id,
      workspaceId: '${map['workspaceId'] ?? ''}',
      name: name,
      normalizedName: '${map['normalizedName'] ?? name.toLowerCase()}'.trim(),
      type: '${map['type'] ?? 'supplier'}',
      createdAt: _parseDate(map['createdAt']),
      attachments: _parseAttachments(map['attachments']),
      lastUsedAt: map['lastUsedAt'] == null
          ? null
          : _parseDate(map['lastUsedAt']),
      clientMutationId: '${map['clientMutationId'] ?? ''}',
    );
  }

  static List<Attachment> _parseAttachments(dynamic value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => Attachment.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    if (value != null) {
      try {
        final converted = (value as dynamic).toDate();
        if (converted is DateTime) {
          return converted;
        }
      } catch (_) {
        // ignored
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'workspaceId': workspaceId,
      'name': name,
      'normalizedName': normalizedName,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      'attachments': attachments
          .map((attachment) => attachment.toMap())
          .toList(),
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      'clientMutationId': clientMutationId,
    };
  }
}
