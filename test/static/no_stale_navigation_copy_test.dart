import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('standalone reports tab localization copy is not retained', () {
    final offenders = <String>[];
    final stalePatterns = [
      'navigationReportsTab',
      "'Reports tab'",
      "'تبويب التقارير'",
    ];

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final content = file.readAsStringSync();
      if (stalePatterns.any(content.contains)) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Reports are project-scoped now, so standalone Reports-tab copy '
          'should not remain in production localization data.',
    );
  });
}
