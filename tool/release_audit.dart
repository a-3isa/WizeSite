import 'dart:convert';
import 'dart:io';

void main() {
  final failures = <String>[];
  final passes = <String>[];

  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  _expectContains(
    source: manifest,
    needle: 'android.permission.INTERNET',
    label: 'AndroidManifest includes INTERNET permission',
    passes: passes,
    failures: failures,
  );
  _expectContains(
    source: manifest,
    needle: 'android.permission.RECORD_AUDIO',
    label: 'AndroidManifest includes RECORD_AUDIO permission',
    passes: passes,
    failures: failures,
  );
  _expectContains(
    source: manifest,
    needle: 'android.permission.READ_CONTACTS',
    label: 'AndroidManifest includes READ_CONTACTS permission',
    passes: passes,
    failures: failures,
  );

  final buildGradle = File('android/app/build.gradle.kts').readAsStringSync();
  _expectContains(
    source: buildGradle,
    needle: 'namespace = "com.ahmed.buildozer"',
    label: 'Android namespace matches release package',
    passes: passes,
    failures: failures,
  );
  _expectContains(
    source: buildGradle,
    needle: 'applicationId = "com.ahmed.buildozer"',
    label: 'Android applicationId matches release package',
    passes: passes,
    failures: failures,
  );

  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  for (final key in const [
    'NSMicrophoneUsageDescription',
    'NSPhotoLibraryUsageDescription',
    'NSCameraUsageDescription',
    'NSContactsUsageDescription',
  ]) {
    _expectContains(
      source: plist,
      needle: '<key>$key</key>',
      label: 'Info.plist includes $key',
      passes: passes,
      failures: failures,
    );
  }

  final googleServices = jsonDecode(
    File('android/app/google-services.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final clients = (googleServices['client'] as List<dynamic>? ?? const [])
      .whereType<Map<dynamic, dynamic>>()
      .map((client) => Map<String, dynamic>.from(client))
      .toList(growable: false);

  final activeClient = clients.cast<Map<String, dynamic>?>().firstWhere(
        (client) =>
            client?['client_info']?['android_client_info']?['package_name'] ==
            'com.ahmed.buildozer',
        orElse: () => null,
      );

  if (activeClient == null) {
    failures.add(
      'google-services.json is missing the com.ahmed.buildozer Android client.',
    );
  } else {
    passes.add('google-services.json includes com.ahmed.buildozer client');
    final oauthClients = (activeClient['oauth_client'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final hasAndroidOauth = oauthClients.any(
      (client) =>
          client['client_type'] == 1 &&
          client['android_info']?['package_name'] == 'com.ahmed.buildozer',
    );
    if (hasAndroidOauth) {
      passes.add(
        'google-services.json includes Android OAuth client for com.ahmed.buildozer',
      );
    } else {
      failures.add(
        'google-services.json is missing Android OAuth client_type 1 for com.ahmed.buildozer. Regenerate it from Firebase Console after adding debug and release SHA fingerprints.',
      );
    }
  }

  stdout.writeln('Release audit results:');
  for (final pass in passes) {
    stdout.writeln('PASS: $pass');
  }
  for (final failure in failures) {
    stdout.writeln('FAIL: $failure');
  }

  if (failures.isNotEmpty) {
    exitCode = 1;
  }
}

void _expectContains({
  required String source,
  required String needle,
  required String label,
  required List<String> passes,
  required List<String> failures,
}) {
  if (source.contains(needle)) {
    passes.add(label);
  } else {
    failures.add(label);
  }
}
