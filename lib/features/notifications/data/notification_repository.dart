import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';

/// Notifications read from the local replica; [markRead] is queued for the
/// `markNotificationsRead` RPC (spec 004, T082).
class NotificationRepository {
  NotificationRepository(this._source, this._mutations);

  final DocSource _source;
  final WorkspaceMutationService _mutations;

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
    await _mutations.markNotificationsRead(ids);
  }
}
