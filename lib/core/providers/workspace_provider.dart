import 'dart:convert';

import 'package:buildtrack_app/core/cache/workspace_cache.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final activeWorkspaceIdProvider = StateProvider<String?>((ref) {
  // Seed from the local cache so a returning user lands on their last
  // workspace instantly, before any network restore completes.
  return ref.watch(workspaceCacheProvider).activeWorkspaceId;
});

final activeUserIdProvider = StateProvider<String?>((ref) {
  return ref.watch(workspaceCacheProvider).activeUserId;
});

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.isOwnedByCurrentUser,
  });

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSummary(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      role: '${json['role'] ?? 'member'}',
      isOwnedByCurrentUser: json['isOwnedByCurrentUser'] == true,
    );
  }

  final String id;
  final String name;
  final String role;
  final bool isOwnedByCurrentUser;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'isOwnedByCurrentUser': isOwnedByCurrentUser,
  };
}

String _encodeWorkspaceSummaries(
  String userId,
  List<WorkspaceSummary> summaries,
) {
  return jsonEncode({
    'userId': userId,
    'items': summaries.map((summary) => summary.toJson()).toList(),
  });
}

/// Decodes cached summaries, returning an empty list when the cache is absent
/// or was written for a different user.
List<WorkspaceSummary> _decodeWorkspaceSummaries(String? json, String userId) {
  if (json == null || json.isEmpty) {
    return const <WorkspaceSummary>[];
  }
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map || '${decoded['userId'] ?? ''}' != userId) {
      return const <WorkspaceSummary>[];
    }
    final items = decoded['items'];
    if (items is! List) {
      return const <WorkspaceSummary>[];
    }
    return items
        .whereType<Map>()
        .map(
          (item) => WorkspaceSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  } catch (_) {
    return const <WorkspaceSummary>[];
  }
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
    final preferredWorkspaceId = next.value;
    if (preferredWorkspaceId == null || preferredWorkspaceId.isEmpty) {
      return;
    }
    if (ref.read(activeWorkspaceIdProvider) == preferredWorkspaceId) {
      return;
    }
    ref.read(activeWorkspaceIdProvider.notifier).state = preferredWorkspaceId;
  }, fireImmediately: true);
});

final activeWorkspaceNameProvider = StreamProvider<String>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return Stream.value('');
  }
  return ref
      .watch(firestoreProvider)
      .collection('workspaces')
      .doc(workspaceId)
      .snapshots()
      .map((snap) => '${snap.data()?['name'] ?? ''}'.trim());
});

final userWorkspaceSummariesProvider = StreamProvider<List<WorkspaceSummary>>((
  ref,
) async* {
  final userId = ref.watch(activeUserIdProvider);
  if (userId == null || userId.isEmpty) {
    yield const <WorkspaceSummary>[];
    return;
  }
  final cache = ref.watch(workspaceCacheProvider);

  // Emit the cached list first so the workspace switcher renders instantly
  // (no loading skeleton); the live stream below refreshes it in the
  // background and rewrites the cache.
  final cached = _decodeWorkspaceSummaries(
    cache.workspaceSummariesJson,
    userId,
  );
  if (cached.isNotEmpty) {
    yield cached;
  }

  final firestore = ref.watch(firestoreProvider);
  yield* firestore
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
        cache.setWorkspaceSummariesJson(
          _encodeWorkspaceSummaries(userId, workspaces),
        );
        return workspaces;
      });
});
