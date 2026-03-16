import 'package:buildtrack_app/firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseInitializer {
  static bool _initialized = false;
  static bool _appCheckActivated = false;
  static const bool _enableDevAppCheck = bool.fromEnvironment(
    'ENABLE_APP_CHECK_DEV',
    defaultValue: false,
  );

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await _ensureAppCheckActivated();
      _initialized = true;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while initializing Firebase'),
        ),
      );
      rethrow;
    }
  }

  static Future<void> _ensureAppCheckActivated() async {
    if (_appCheckActivated || kIsWeb) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android App Check provider is installed natively in MainApplication.
      _appCheckActivated = true;
      return;
    }

    if (!kReleaseMode && !_enableDevAppCheck) {
      _appCheckActivated = true;
      return;
    }

    try {
      if (!kReleaseMode) {
        await FirebaseAppCheck.instance.activate(
          providerApple: const AppleDebugProvider(),
        );
      } else {
        await FirebaseAppCheck.instance.activate(
          providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      }
      _appCheckActivated = true;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while activating Firebase App Check'),
        ),
      );
    }
  }
}
