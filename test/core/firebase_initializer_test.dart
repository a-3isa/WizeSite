import 'package:buildtrack_app/core/services/firebase_initializer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses Apple debug App Check on iOS debug builds', () {
    final mode = FirebaseInitializer.appCheckActivationMode(
      isWeb: false,
      isReleaseMode: false,
      platform: TargetPlatform.iOS,
    );

    expect(mode, AppCheckActivationMode.appleDebug);
  });

  test('uses Play Integrity on Android release builds', () {
    final mode = FirebaseInitializer.appCheckActivationMode(
      isWeb: false,
      isReleaseMode: true,
      platform: TargetPlatform.android,
    );

    expect(mode, AppCheckActivationMode.androidRelease);
  });

  test('skips App Check activation on web', () {
    final mode = FirebaseInitializer.appCheckActivationMode(
      isWeb: true,
      isReleaseMode: true,
      platform: TargetPlatform.android,
    );

    expect(mode, AppCheckActivationMode.skip);
  });
}
