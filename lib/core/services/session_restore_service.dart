import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/app_telemetry.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/local_session_cleanup.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionRestoreResult {
  const SessionRestoreResult({
    required this.userId,
    required this.workspaceId,
    required this.setupCompleted,
  });

  final String userId;
  final String workspaceId;
  final bool setupCompleted;
}

class SessionRestoreService {
  const SessionRestoreService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required CallableClient callableClient,
    required AppTelemetry telemetry,
    Future<void> Function()? onSignOutCleanup,
  }) : _auth = auth,
       _firestore = firestore,
       _callableClient = callableClient,
       _telemetry = telemetry,
       _onSignOutCleanup = onSignOutCleanup;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final CallableClient _callableClient;
  final AppTelemetry _telemetry;
  final Future<void> Function()? _onSignOutCleanup;

  Future<SessionRestoreResult?> restore() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    try {
      await _telemetry.log('session_restore.start', {'user_id': user.uid});
      final workspace = await _resolveWorkspaceId(user);
      if (workspace == null || workspace.workspaceId.isEmpty) {
        await _telemetry.log('session_restore.no_workspace', {
          'user_id': user.uid,
        });
        await _signOutToBreakStrandedSessionLoop();
        return null;
      }

      await _telemetry.log('session_restore.success', {
        'user_id': user.uid,
        'workspace_id': workspace.workspaceId,
      });
      return SessionRestoreResult(
        userId: user.uid,
        workspaceId: workspace.workspaceId,
        setupCompleted: workspace.setupCompleted,
      );
    } catch (error, stackTrace) {
      // Any unexpected failure here (e.g. telemetry/Crashlytics plumbing not
      // yet warm on a freshly (re)installed app, a transient plugin-channel
      // error) must still break the stranded-session loop the same way a
      // clean "no workspace" result does. Left unguarded, such an exception
      // bypasses the sign-out below entirely: it propagates out of restore(),
      // the caller's catch swallows it, and the user is left signed in with
      // no workspace forever, bouncing between splash and login with no path
      // to an actual login form.
      try {
        await _telemetry.recordError(
          error,
          stackTrace,
          reason: 'session_restore.unexpected',
        );
      } catch (_) {
        // Telemetry itself may be what failed; don't let recording the
        // failure become a second failure.
      }
      await _signOutToBreakStrandedSessionLoop();
      return null;
    }
  }

  // A cached Firebase session that can't be fully restored would otherwise
  // strand the user: the router treats "signed in" as authoritative and
  // bounces any visit to /login or /signup straight back to the splash
  // screen to retry this same restore, which fails the same way forever
  // with no path back to an actual login form. Signing out breaks that loop.
  Future<void> _signOutToBreakStrandedSessionLoop() async {
    final cleanup = _onSignOutCleanup;
    if (cleanup != null) {
      try {
        await cleanup();
      } catch (_) {
        // Hive may not be open yet; still sign out.
      }
    }
    try {
      await _auth.signOut();
    } catch (_) {
      // Best effort; nothing more we can do if sign-out itself fails.
    }
  }

  Future<WorkspaceBootstrapResult?> _resolveWorkspaceId(User user) async {
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final workspaceId = userDoc.data()?['workspaceId'] as String?;
      if (workspaceId != null && workspaceId.isNotEmpty) {
        await _ensureOwnerMembership(user: user, workspaceId: workspaceId);
        return WorkspaceBootstrapResult(
          workspaceId: workspaceId,
          created: false,
          setupCompleted: userDoc.data()?['setupCompleted'] as bool? ?? true,
        );
      }

      final membershipSnap = await _firestore
          .collection('memberships')
          .where('userId', isEqualTo: user.uid)
          .get();
      final workspaceIds =
          membershipSnap.docs
              .map((doc) => doc.data()['workspaceId'] as String?)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
            ..sort();
      if (workspaceIds.isNotEmpty) {
        return WorkspaceBootstrapResult(
          workspaceId: workspaceIds.first,
          created: false,
          setupCompleted: true,
        );
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

  Future<WorkspaceBootstrapResult?> _bootstrapWorkspaceId() async {
    try {
      return await _callableClient.call<WorkspaceBootstrapResult>(
        functionName: 'ensureUserWorkspaceBootstrap',
        payload: const {},
        parseResult: (result) {
          final data = Map<String, dynamic>.from(result as Map);
          return WorkspaceBootstrapResult.fromMap(data);
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
    onSignOutCleanup: LocalSessionCleanup.clearQueuedUserData,
  );
});
