import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release build strips dev-only generated plugin registrations', () {
    final buildFile = File('android/app/build.gradle.kts').readAsStringSync();

    expect(buildFile, contains('sanitizeReleaseGeneratedPluginRegistrant'));
    expect(buildFile, contains('flutter_native_splash'));
    expect(buildFile, contains('integration_test'));
  });

  test(
    'release Crashlytics mapping upload runs unless explicitly disabled',
    () {
      final buildFile = File('android/app/build.gradle.kts').readAsStringSync();

      expect(buildFile, contains('uploadCrashlyticsMappingFileRelease'));
      expect(buildFile, contains('UPLOAD_CRASHLYTICS_MAPPING'));
      expect(buildFile, contains('!it.equals("false", ignoreCase = true)'));
      expect(buildFile, contains('.orElse(true)'));
    },
  );
}
