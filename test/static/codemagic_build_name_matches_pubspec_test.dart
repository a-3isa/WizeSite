import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Codemagic iOS builds use the pubspec version name', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final yamlMatch = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(yamlMatch, isNotNull, reason: 'pubspec.yaml must declare version');
    final versionName = yamlMatch!.group(1)!;

    final yaml = File('codemagic.yaml').readAsStringSync();
    expect(
      yaml.contains('--build-name=1.0.0'),
      isFalse,
      reason: 'Hardcoded 1.0.0 ships a stale App Store version',
    );
    expect(
      yaml.contains('PUBSPEC_VERSION') || yaml.contains(versionName),
      isTrue,
      reason: 'Codemagic must read $versionName from pubspec',
    );
    expect(
      yaml.contains('android_release_artifact'),
      isTrue,
      reason: 'Codemagic must include an Android workflow',
    );
    expect(
      yaml.contains('node: 22'),
      isTrue,
      reason: 'Functions CI must pin Node 22',
    );
  });

  test('iOS Privacy Manifest is present', () {
    expect(File('ios/Runner/PrivacyInfo.xcprivacy').existsSync(), isTrue);
  });
}
