import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider loading branches do not render blank placeholders', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'loading\s*:\s*\(\)\s*=>\s*const\s+SizedBox\.shrink\s*\(',
      multiLine: true,
    );

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final content = file.readAsStringSync();
      if (pattern.hasMatch(content)) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Async loading branches should use a visible skeleton or progress '
          'indicator instead of a blank widget.',
    );
  });

  test('screen-level loading branches use skeletons instead of lone spinners', () {
    final offenders = <String>[];
    final patterns = [
      RegExp(
        r'\?\s*const\s+Center\s*\(\s*child:\s*CircularProgressIndicator\s*\(',
      ),
      RegExp(
        r'loading\s*:\s*\(\)\s*=>\s*const\s+Center\s*\(\s*child:\s*CircularProgressIndicator\s*\(',
      ),
      RegExp(
        r'return\s+const\s+Center\s*\(\s*child:\s*CircularProgressIndicator\s*\(',
      ),
    ];

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final content = file.readAsStringSync();
      if (patterns.any((pattern) => pattern.hasMatch(content))) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Screen-level loading should show stable skeleton content; reserve '
          'plain spinners for buttons, pagination, or other inline progress.',
    );
  });
}
