import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationRepository {
  NotificationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<NotificationItem>> watchTargeted({
    required String workspaceId,
    required String userId,
    int limit = 50,
  }) {
    return _firestore
        .collection('notifications')
        .where('workspaceId', isEqualTo: workspaceId)
        .where('targetUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationItem.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<void> markRead(Iterable<String> notificationIds) async {
    final ids = notificationIds.toSet();
    if (ids.isEmpty) return;
    final batch = _firestore.batch();
    final readAt = FieldValue.serverTimestamp();
    for (final id in ids) {
      batch.update(_firestore.collection('notifications').doc(id), {
        'readAt': readAt,
      });
    }
    await batch.commit();
  }
}
