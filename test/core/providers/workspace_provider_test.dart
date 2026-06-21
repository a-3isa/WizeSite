import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'workspace list includes memberships and owned personal workspace',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('workspaces').doc('personal_ws').set({
        'id': 'personal_ws',
        'name': 'My Personal Workspace',
        'ownerId': 'user_1',
      });
      await firestore.collection('workspaces').doc('shared_ws').set({
        'id': 'shared_ws',
        'name': 'Shared Client Workspace',
        'ownerId': 'owner_2',
      });
      await firestore.collection('memberships').doc('shared_ws_user_1').set({
        'workspaceId': 'shared_ws',
        'userId': 'user_1',
        'role': 'member',
      });

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
        ],
      );
      addTearDown(container.dispose);

      final workspaces = await container.read(
        userWorkspaceSummariesProvider.future,
      );

      expect(workspaces.map((workspace) => workspace.id), [
        'personal_ws',
        'shared_ws',
      ]);
      expect(workspaces.first.role, 'owner');
      expect(workspaces.first.isOwnedByCurrentUser, isTrue);
    },
  );

  test(
    'workspace sync updates active workspace when invite changes user doc',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('user_1').set({
        'workspaceId': 'personal_ws',
      });

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          activeUserIdProvider.overrideWith((ref) => 'user_1'),
          activeWorkspaceIdProvider.overrideWith((ref) => 'personal_ws'),
        ],
      );
      addTearDown(container.dispose);

      container.read(workspaceSelectionSyncProvider);
      await firestore.collection('users').doc('user_1').set({
        'workspaceId': 'invited_ws',
      }, SetOptions(merge: true));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(activeWorkspaceIdProvider), 'invited_ws');
    },
  );
}
