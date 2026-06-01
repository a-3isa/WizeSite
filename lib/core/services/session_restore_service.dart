import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionRestoreResult {
  const SessionRestoreResult({required this.userId, required this.workspaceId});

  final String userId;
  final String workspaceId;
}

class SessionRestoreService {
  const SessionRestoreService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required CallableClient callableClient,
    required AppTelemetry telemetry,
  }) : _auth = auth,
       _firestore = firestore,
       _callableClient = callableClient,
       _telemetry = telemetry;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final CallableClient _callableClient;
  final AppTelemetry _telemetry;

  Future<SessionRestoreResult?> restore() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    await _telemetry.log('session_restore.start', {'user_id': user.uid});
    final workspaceId = await _resolveWorkspaceId(user);
    if (workspaceId == null || workspaceId.isEmpty) {
      await _telemetry.log('session_restore.no_workspace', {'user_id': user.uid});
      return null;
    }

    await _telemetry.log('session_restore.success', {
      'user_id': user.uid,
      'workspace_id': workspaceId,
    });
    return SessionRestoreResult(userId: user.uid, workspaceId: workspaceId);
  }

  Future<String?> _resolveWorkspaceId(User user) async {
    try {
      final membershipSnap = await _firestore
          .collection('memberships')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (membershipSnap.docs.isNotEmpty) {
        final workspaceId =
            membershipSnap.docs.first.data()['workspaceId'] as String?;
        if (workspaceId != null && workspaceId.isNotEmpty) {
          return workspaceId;
        }
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final workspaceId = userDoc.data()?['workspaceId'] as String?;
      if (workspaceId != null && workspaceId.isNotEmpty) {
        await _ensureOwnerMembership(user: user, workspaceId: workspaceId);
        return workspaceId;
      }
    } catch (error, stackTrace) {
      await _telemetry.recordError(
        error,
        stackTrace,
        reason: 'session_restore.resolve_workspace',
      );
      // Firestore platform channel unavailable; fall through to callable.
    }

    return _bootstrapWorkspaceId();
  }

  Future<void> _ensureOwnerMembership({
    required User user,
    required String workspaceId,
  }) async {
    final workspaceSnap = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .get();
    final ownerId = workspaceSnap.data()?['ownerId'] as String?;
    if (ownerId != user.uid) {
      return;
    }
    final membershipRef = _firestore
        .collection('memberships')
        .doc('${workspaceId}_${user.uid}');
    final membershipSnap = await membershipRef.get();
    if (membershipSnap.exists) {
      return;
    }

    await membershipRef.set({
      'workspaceId': workspaceId,
      'userId': user.uid,
      'role': 'owner',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> _bootstrapWorkspaceId() async {
    try {
      return await _callableClient.call<String>(
        functionName: 'ensureUserWorkspaceBootstrap',
        payload: const {},
        parseResult: (result) {
          final data = Map<String, dynamic>.from(result as Map);
          final workspaceId = '${data['workspaceId'] ?? ''}'.trim();
          return workspaceId;
        },
        defaultErrorMessage: 'Failed to restore your workspace.',
      );
    } catch (error, stackTrace) {
      await _telemetry.recordError(
        error,
        stackTrace,
        reason: 'session_restore.bootstrap',
      );
      return null;
    }
  }
}

final sessionRestoreServiceProvider = Provider<SessionRestoreService>((ref) {
  return SessionRestoreService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
    callableClient: ref.watch(callableClientProvider),
    telemetry: ref.watch(appTelemetryProvider),
  );
});
