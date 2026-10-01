import 'package:buildtrack_app/firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum AppCheckActivationMode {
  skip,
  androidDebug,
  androidRelease,
  appleDebug,
  appleRelease,
}

class FirebaseInitializer {
  static bool _initialized = false;
  static bool _appCheckActivated = false;

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
    if (_appCheckActivated) {
      return;
    }
    final mode = appCheckActivationMode(
      isWeb: kIsWeb,
      isReleaseMode: kReleaseMode,
      platform: defaultTargetPlatform,
    );
    if (mode == AppCheckActivationMode.skip) {
      _appCheckActivated = true;
      return;
    }

    try {
      if (mode == AppCheckActivationMode.androidDebug) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidDebugProvider(),
        );
      } else if (mode == AppCheckActivationMode.androidRelease) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
        );
      } else if (mode == AppCheckActivationMode.appleDebug) {
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

  @visibleForTesting
  static AppCheckActivationMode appCheckActivationMode({
    required bool isWeb,
    required bool isReleaseMode,
    required TargetPlatform platform,
  }) {
    if (isWeb) {
      return AppCheckActivationMode.skip;
    }
    switch (platform) {
      case TargetPlatform.android:
        return isReleaseMode
            ? AppCheckActivationMode.androidRelease
            : AppCheckActivationMode.androidDebug;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return isReleaseMode
            ? AppCheckActivationMode.appleRelease
            : AppCheckActivationMode.appleDebug;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return AppCheckActivationMode.skip;
    }
  }
}
