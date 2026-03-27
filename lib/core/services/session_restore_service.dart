import 'package:buildtrack_app/core/providers/firebase_providers.dart';
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
  }) : _auth = auth,
       _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<SessionRestoreResult?> restore() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    final workspaceId = await _resolveWorkspaceId(user);
    if (workspaceId == null || workspaceId.isEmpty) {
      return null;
    }

    return SessionRestoreResult(userId: user.uid, workspaceId: workspaceId);
  }

  Future<String?> _resolveWorkspaceId(User user) async {
    final membershipSnap = await _firestore
        .collection('memberships')
        .where('userId', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (membershipSnap.docs.isNotEmpty) {
      final workspaceId =
          membershipSnap.docs.first.data()['workspaceId'] as String?;
      if (workspaceId != null && workspaceId.isNotEmpty) {
        await _syncUserWorkspace(user.uid, workspaceId);
        return workspaceId;
      }
    }

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final workspaceId = userDoc.data()?['workspaceId'] as String?;
    if (workspaceId != null && workspaceId.isNotEmpty) {
      return workspaceId;
    }

    return null;
  }

  Future<void> _syncUserWorkspace(String userId, String workspaceId) async {
    await _firestore.collection('users').doc(userId).set({
      'workspaceId': workspaceId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

final sessionRestoreServiceProvider = Provider<SessionRestoreService>((ref) {
  return SessionRestoreService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
  );
});
