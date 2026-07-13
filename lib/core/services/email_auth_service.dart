import 'package:firebase_auth/firebase_auth.dart';

/// Email + password authentication against Firebase Auth.
///
/// Kept deliberately thin: it owns the Firebase calls and nothing else, so the
/// screens stay responsible for validation/presentation and the workspace
/// bootstrap (a Cloud Function) stays shared with the Google sign-in path.
class EmailAuthService {
  const EmailAuthService();

  /// Signs an existing user in. Throws [FirebaseAuthException] on failure.
  Future<UserCredential> signIn({
    required FirebaseAuth auth,
    required String email,
    required String password,
  }) {
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates an account and stores [displayName] on the Firebase user profile.
  ///
  /// The display name is set before returning so the rest of the app (workspace
  /// bootstrap, profile screen) sees a fully-populated user on first read.
  Future<UserCredential> signUp({
    required FirebaseAuth auth,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final name = displayName.trim();
    final user = credential.user;
    if (name.isNotEmpty && user != null) {
      await user.updateDisplayName(name);
      // Ensure the in-memory user reflects the new profile for immediate reads.
      await user.reload();
    }
    return credential;
  }

  /// Sends a password-reset email. Throws [FirebaseAuthException] on failure.
  Future<void> sendPasswordReset({
    required FirebaseAuth auth,
    required String email,
  }) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }
}
