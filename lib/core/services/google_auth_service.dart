import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;
  bool _initialized = false;

  /// True if Google Sign-In is available on this platform (e.g. Android, iOS, Web with config).
  Future<bool> get isSupported async {
    await _initializeIfNeeded();
    return _googleSignIn.supportsAuthenticate();
  }

  Future<UserCredential?> signInWithGoogle({required FirebaseAuth auth}) async {
    await _initializeIfNeeded();

    if (!_googleSignIn.supportsAuthenticate()) {
      return null;
    }

    try {
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google Sign-In returned no ID token.');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return null;
        default:
          throw StateError(
            'Google Sign-In failed: ${e.description ?? e.code.name}',
          );
      }
    }
  }

  Future<void> signOut() async {
    if (!_initialized) {
      return;
    }

    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore Google sign-out errors so app logout still succeeds.
    }
  }

  Future<void> _initializeIfNeeded() async {
    if (_initialized) {
      return;
    }

    // serverClientId is not supported on Web; client ID comes from meta tag in web/index.html.
    final rawId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue:
          '549941684400-p03oaa7s7kf66ndscjshia7b5hb7cheg.apps.googleusercontent.com',
    );
    final serverClientId = kIsWeb ? null : (rawId.isEmpty ? null : rawId);

    await _googleSignIn.initialize(serverClientId: serverClientId);
    _initialized = true;
  }
}
