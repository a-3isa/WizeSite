import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.workspaceId,
    required this.targetUserId,
    required this.title,
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String workspaceId;
  final String targetUserId;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory NotificationItem.fromMap(String id, Map<String, dynamic> data) {
    return NotificationItem(
      id: id,
      workspaceId: '${data['workspaceId'] ?? ''}',
      targetUserId: '${data['targetUserId'] ?? ''}',
      title: '${data['title'] ?? ''}',
      message: '${data['message'] ?? ''}',
      createdAt:
          _date(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      readAt: _date(data['readAt']),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
