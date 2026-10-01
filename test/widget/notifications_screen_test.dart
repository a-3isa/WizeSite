import 'package:buildtrack_app/features/notifications/data/notification_repository.dart';
import 'package:buildtrack_app/features/notifications/domain/notification_item.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/local_fixture_store.dart';

class _MockMutations extends Mock implements WorkspaceMutationService {}

void main() {
  test('missing readAt remains unread for backward compatibility', () {
    final item = NotificationItem.fromMap('notice_1', {
      'workspaceId': 'workspace_1',
      'targetUserId': 'user_1',
      'title': 'Updated',
      'message': 'A record changed',
      'createdAt': DateTime(2026, 6, 15),
    });

    expect(item.isUnread, isTrue);
    expect(item.readAt, isNull);
  });

  test('readAt marks a notification as read', () {
    final item = NotificationItem.fromMap('notice_1', {
      'workspaceId': 'workspace_1',
      'targetUserId': 'user_1',
      'title': 'Updated',
      'message': 'A record changed',
      'createdAt': DateTime(2026, 6, 15),
      'readAt': DateTime(2026, 6, 15, 1),
    });

    expect(item.isUnread, isFalse);
  });

  test(
    'repository returns only the bounded targeted feed and marks read',
    () async {
      final firestore = await LocalFixtureStore.open();
      addTearDown(firestore.dispose);
      for (var index = 0; index < 52; index += 1) {
        await firestore.collection('notifications').doc('notice_$index').set({
          'workspaceId': 'workspace_1',
          'targetUserId': 'user_1',
          'title': 'Notice $index',
          'message': 'Message',
          'createdAt': DateTime(2026, 6, 15).add(Duration(minutes: index)),
        });
      }
      await firestore.collection('notifications').doc('other').set({
        'workspaceId': 'workspace_1',
        'targetUserId': 'user_2',
        'title': 'Other user',
        'message': 'Hidden',
        'createdAt': DateTime(2026, 6, 16),
      });
      final mutations = _MockMutations();
      when(
        () => mutations.markNotificationsRead(any()),
      ).thenAnswer((_) async => const MutationResult(queued: true));
      final repository = NotificationRepository(firestore.source, mutations);

      final items = await repository
          .watchTargeted(workspaceId: 'workspace_1', userId: 'user_1')
          .first;
      expect(items, hasLength(50));
      expect(items.every((item) => item.targetUserId == 'user_1'), isTrue);

      await repository.markRead([items.first.id]);
      verify(() => mutations.markNotificationsRead({items.first.id})).called(1);
    },
  );
}
