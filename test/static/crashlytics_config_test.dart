import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS Crashlytics app matches the shipping bundle id', () {
    const appId = '1:549941684400:ios:19edd9d2ec4448d68e7375';
    const bundleId = 'com.ahmed.buildozer';
    const reversedClientId =
        'com.googleusercontent.apps.549941684400-fveof93eklftudeup0il9q3t34i8hfga';

    final plist = File(
      'ios/Runner/GoogleService-Info.plist',
    ).readAsStringSync();
    final options = File('lib/firebase_options.dart').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(plist, contains('<string>$bundleId</string>'));
    expect(plist, contains('<string>$appId</string>'));
    expect(options, contains("appId: '$appId'"));
    expect(options, contains("iosBundleId: '$bundleId'"));
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = $bundleId;'));
    expect(project, contains('GoogleService-Info.plist in Resources'));
    expect(infoPlist, contains(reversedClientId));
    expect(main, contains('fatal: true'));
    expect(main, isNot(contains('fatal: false')));
  });
}
