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
    this.defaultRate,
    this.rateUnit = '',
    this.phoneNumber = '',
    this.notes = '',
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
  final double? defaultRate;
  final String rateUnit;
  final String phoneNumber;
  final String notes;

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
      defaultRate: (map['defaultRate'] as num?)?.toDouble(),
      rateUnit: '${map['rateUnit'] ?? ''}',
      phoneNumber: '${map['phoneNumber'] ?? ''}',
      notes: '${map['notes'] ?? ''}',
    );
  }

  static List<Attachment> _parseAttachments(dynamic value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map<dynamic, dynamic>>()
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
      if (defaultRate != null) 'defaultRate': defaultRate,
      if (rateUnit.isNotEmpty) 'rateUnit': rateUnit,
      if (phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
      if (notes.isNotEmpty) 'notes': notes,
    };
  }
}
