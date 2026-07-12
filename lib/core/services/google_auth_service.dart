import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';

/// Thrown when Google reports the OAuth client itself is misconfigured (SHA
/// fingerprint not registered/propagated yet, package name mismatch, etc.),
/// as opposed to the user simply backing out of the account picker.
class GoogleSignInConfigException implements Exception {
  GoogleSignInConfigException(this.description);
  final String? description;

  @override
  String toString() => 'GoogleSignInConfigException: $description';
}

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
      debugPrint(
        'GoogleAuthService: supportsAuthenticate() is false — Google Play '
        'Services / Credential Manager provider unavailable on this device.',
      );
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
      // Always log the real code: canceled/interrupted here can mean a
      // genuine user tap-back, but it's also what Google's SDK reports when
      // the OAuth client's SHA fingerprint isn't registered/propagated yet —
      // logcat is the only way to tell those apart after the fact.
      debugPrint(
        'GoogleAuthService: sign-in exception ${e.code.name}: '
        '${e.description ?? "(no description)"}',
      );
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw GoogleSignInConfigException(e.description);
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

    // Apple platforms need the iOS OAuth client ID. The plugin would normally
    // read it from a bundled GoogleService-Info.plist, but that file is not in
    // the app bundle (Firebase initializes from firebase_options.dart instead),
    // so authenticate() fails immediately on iOS unless we pass it explicitly.
    final rawClientId = const String.fromEnvironment(
      'GOOGLE_IOS_CLIENT_ID',
      defaultValue:
          '549941684400-hjq57nnh3rrmavc1fgsfrjdebdqd271h.apps.googleusercontent.com',
    );
    final isApple =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final clientId = (isApple && rawClientId.isNotEmpty) ? rawClientId : null;

    await _googleSignIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
    _initialized = true;
  }
}
