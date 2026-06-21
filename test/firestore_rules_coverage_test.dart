import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard against the class of production bug where client code reads/writes a
/// Firestore collection that has **no `match` block** in `firestore.rules` —
/// which silently falls through to default-deny (PERMISSION_DENIED at runtime,
/// invisible to widget tests that use fakes).
///
/// Scans every string-literal `.collection('name')` in `lib/` and asserts each
/// has a corresponding `match /name/{…}` block in `firestore.rules`.
void main() {
  test('every client-accessed collection has a firestore.rules match block',
      () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'run from repo root');

    final collectionLiteral = RegExp(
      r'''\.collection\(\s*['"]([a-zA-Z_][a-zA-Z0-9_]*)['"]''',
    );

    final clientCollections = <String>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final match in collectionLiteral.allMatches(entity.readAsStringSync())) {
        clientCollections.add(match.group(1)!);
      }
    }
    expect(clientCollections, isNotEmpty,
        reason: 'expected to find .collection() usages in lib/');

    final rules = File('firestore.rules').readAsStringSync();
    final ruleMatch = RegExp(r'match\s+/([a-zA-Z_][a-zA-Z0-9_]*)/');
    final ruledCollections = <String>{
      for (final m in ruleMatch.allMatches(rules)) m.group(1)!,
    };

    final missing = clientCollections.difference(ruledCollections).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'These collections are accessed from lib/ but have NO match block in '
          'firestore.rules (default-deny → PERMISSION_DENIED in production): '
          '$missing',
    );
  });
}
