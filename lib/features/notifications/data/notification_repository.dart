import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationRepository {
  NotificationRepository(this._firestore)
    : _source = FirestoreDocSource(_firestore),
      _mutations = null;

  /// Reads through [source] (local replica in self-hosted builds, spec 004).
  /// With [mutations], [markRead] is queued for `markNotificationsRead`
  /// (T082) instead of written to Firestore.
  NotificationRepository.withSource(
    this._firestore,
    this._source, {
    WorkspaceMutationService? mutations,
  }) : _mutations = mutations;

  final FirebaseFirestore _firestore;
  final DocSource _source;
  final WorkspaceMutationService? _mutations;

  Stream<List<NotificationItem>> watchTargeted({
    required String workspaceId,
    required String userId,
    int limit = 50,
  }) {
    return _source
        .watch(
          DocQuery(
            'notifications',
            equals: {'workspaceId': workspaceId, 'targetUserId': userId},
            orderBy: 'createdAt',
            descending: true,
            limit: limit,
          ),
        )
        .map(
          (docs) => docs
              .map((doc) => NotificationItem.fromMap(doc.id, doc.data))
              .toList(growable: false),
        );
  }

  Future<void> markRead(Iterable<String> notificationIds) async {
    final ids = notificationIds.toSet();
    if (ids.isEmpty) return;
    final mutations = _mutations;
    if (mutations != null) {
      await mutations.markNotificationsRead(ids);
      return;
    }
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
