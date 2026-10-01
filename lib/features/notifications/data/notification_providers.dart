import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/notifications/data/notification_repository.dart';
import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    ref.watch(docSourceProvider),
    ref.watch(workspaceMutationServiceProvider),
  );
});

final notificationItemsProvider = StreamProvider<List<NotificationItem>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final userId = ref.watch(activeUserIdProvider);
  if (workspaceId == null ||
      workspaceId.isEmpty ||
      userId == null ||
      userId.isEmpty) {
    return Stream.value(const []);
  }
  return ref
      .watch(notificationRepositoryProvider)
      .watchTargeted(workspaceId: workspaceId, userId: userId);
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref
          .watch(notificationItemsProvider)
          .value
          ?.where((item) => item.isUnread)
          .length ??
      0;
});
