import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final activeWorkspaceIdProvider = StateProvider<String?>((ref) {
  return null;
});

final activeUserIdProvider = StateProvider<String?>((ref) {
  return null;
});

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.isOwnedByCurrentUser,
  });

  final String id;
  final String name;
  final String role;
  final bool isOwnedByCurrentUser;
}

final userPreferredWorkspaceIdProvider = StreamProvider<String?>((ref) {
  final userId = ref.watch(activeUserIdProvider);
  if (userId == null || userId.isEmpty) {
    return Stream.value(null);
  }
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((snap) => '${snap.data()?['workspaceId'] ?? ''}'.trim())
      .map((workspaceId) => workspaceId.isEmpty ? null : workspaceId);
});

final workspaceSelectionSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<String?>>(userPreferredWorkspaceIdProvider, (
    previous,
    next,
  ) {
    final preferredWorkspaceId = next.valueOrNull;
    if (preferredWorkspaceId == null || preferredWorkspaceId.isEmpty) {
      return;
    }
    if (ref.read(activeWorkspaceIdProvider) == preferredWorkspaceId) {
      return;
    }
    ref.read(activeWorkspaceIdProvider.notifier).state = preferredWorkspaceId;
  }, fireImmediately: true);
});

final userWorkspaceSummariesProvider = StreamProvider<List<WorkspaceSummary>>((
  ref,
) {
  final userId = ref.watch(activeUserIdProvider);
  if (userId == null || userId.isEmpty) {
    return Stream.value(const <WorkspaceSummary>[]);
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('memberships')
      .where('userId', isEqualTo: userId)
      .snapshots()
      .asyncMap((membershipSnapshot) async {
        final summaries = <String, WorkspaceSummary>{};

        Future<void> addWorkspace({
          required String workspaceId,
          required String role,
        }) async {
          if (workspaceId.isEmpty) {
            return;
          }
          final workspaceSnap = await firestore
              .collection('workspaces')
              .doc(workspaceId)
              .get();
          final workspaceData = workspaceSnap.data() ?? const {};
          final ownerId = '${workspaceData['ownerId'] ?? ''}'.trim();
          final name = '${workspaceData['name'] ?? ''}'.trim();
          final isOwner = ownerId == userId || role == 'owner';
          summaries[workspaceId] = WorkspaceSummary(
            id: workspaceId,
            name: name.isEmpty ? 'Workspace' : name,
            role: isOwner ? 'owner' : role,
            isOwnedByCurrentUser: ownerId == userId,
          );
        }

        for (final doc in membershipSnapshot.docs) {
          final data = doc.data();
          await addWorkspace(
            workspaceId: '${data['workspaceId'] ?? ''}'.trim(),
            role: '${data['role'] ?? 'member'}'.trim(),
          );
        }

        final ownedWorkspaces = await firestore
            .collection('workspaces')
            .where('ownerId', isEqualTo: userId)
            .get();
        for (final doc in ownedWorkspaces.docs) {
          await addWorkspace(workspaceId: doc.id, role: 'owner');
        }

        final workspaces = summaries.values.toList()
          ..sort((a, b) {
            if (a.isOwnedByCurrentUser != b.isOwnedByCurrentUser) {
              return a.isOwnedByCurrentUser ? -1 : 1;
            }
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        return workspaces;
      });
});
