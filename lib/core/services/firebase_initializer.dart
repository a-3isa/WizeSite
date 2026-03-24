import 'package:buildtrack_app/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseInitializer {
  static bool _initialized = false;
  static bool _appCheckActivated = false;
  static const String _androidDebugAppCheckToken =
      '4977E101-6CA1-4EAF-B50D-6B32AD6A1B3B';
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
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
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

    if (!kReleaseMode &&
        !_enableDevAppCheck &&
        defaultTargetPlatform != TargetPlatform.android) {
      _appCheckActivated = true;
      return;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: !kReleaseMode
              ? const AndroidDebugProvider(
                  debugToken: _androidDebugAppCheckToken,
                )
              : const AndroidPlayIntegrityProvider(),
        );
      } else if (!kReleaseMode) {
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
