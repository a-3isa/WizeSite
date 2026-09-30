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

  /// Confirms the current password so sensitive actions (account deletion)
  /// can refresh Firebase `auth_time`.
  Future<UserCredential> reauthenticate({
    required User user,
    required String password,
  }) {
    final email = user.email?.trim() ?? '';
    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'user-mismatch',
        message: 'This account has no email to reauthenticate with.',
      );
    }
    return user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  /// Sends (or re-sends) the address-verification email to the current user.
  Future<void> sendVerificationEmail({required FirebaseAuth auth}) async {
    final user = auth.currentUser;
    if (user == null || user.emailVerified) {
      return;
    }
    await user.sendEmailVerification();
  }

  /// Re-fetches the user from Firebase and reports whether the address is now
  /// verified.
  ///
  /// [User.emailVerified] is a snapshot taken at sign-in; clicking the link in
  /// the email does not push an update to the client, so the only way to observe
  /// it is to reload.
  Future<bool> refreshEmailVerified({required FirebaseAuth auth}) async {
    final user = auth.currentUser;
    if (user == null) {
      return false;
    }
    await user.reload();
    return auth.currentUser?.emailVerified ?? false;
  }
}

/// True when [user] signed up with email/password and has not verified yet.
///
/// Federated identities (Google) arrive pre-verified, so they must never be
/// caught by the verification gate.
bool requiresEmailVerification(User? user) {
  if (user == null || user.emailVerified) {
    return false;
  }
  return user.providerData.any((provider) => provider.providerId == 'password');
}
