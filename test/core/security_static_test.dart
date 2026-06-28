import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App Check debug tokens are not hardcoded or logged', () {
    final paths = [
      'lib/core/services/firebase_initializer.dart',
      'android/app/src/debug/kotlin/com/ahmed/buildozer/AppCheckSetup.kt',
    ];
    final uuidPattern = RegExp(
      r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}',
    );

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        uuidPattern.hasMatch(source),
        isFalse,
        reason: '$path must not contain a literal App Check debug token.',
      );
      expect(
        source,
        isNot(contains('token=')),
        reason: '$path must not log App Check token values.',
      );
    }
  });

  test('gitignore blocks common local secret files', () {
    final gitignore = File('.gitignore').readAsStringSync();

    for (final pattern in [
      '.env',
      '.env.*',
      'functions/.env*',
      'google-services.json',
      'GoogleService-Info.plist',
      '*-firebase-adminsdk-*.json',
      '*service-account*.json',
      '*service_account*.json',
    ]) {
      expect(
        gitignore,
        contains(pattern),
        reason: '.gitignore should protect $pattern from accidental commits.',
      );
    }
  });

  test('debug logs do not print financial payload details', () {
    final sourceByPath = {
      'lib/core/services/callable_client.dart': File(
        'lib/core/services/callable_client.dart',
      ).readAsStringSync(),
      'lib/core/services/offline_action_queue.dart': File(
        'lib/core/services/offline_action_queue.dart',
      ).readAsStringSync(),
      'lib/core/services/workspace_mutation_service.dart': File(
        'lib/core/services/workspace_mutation_service.dart',
      ).readAsStringSync(),
      'lib/features/payments/data/payment_repository.dart': File(
        'lib/features/payments/data/payment_repository.dart',
      ).readAsStringSync(),
      'lib/features/projects/data/project_repository.dart': File(
        'lib/features/projects/data/project_repository.dart',
      ).readAsStringSync(),
    };

    final forbiddenByPath = {
      'lib/core/services/callable_client.dart': [
        'body=\${response.body}',
        'details=\${error.details}',
        'details=\${retryError.details}',
      ],
      'lib/core/services/offline_action_queue.dart': ['[offline_queue.'],
      'lib/core/services/workspace_mutation_service.dart': [
        '[mutation.createPayment]',
      ],
      'lib/features/payments/data/payment_repository.dart': ['[payment_repo.'],
      'lib/features/projects/data/project_repository.dart': ['[project_repo.'],
    };

    for (final entry in forbiddenByPath.entries) {
      final source = sourceByPath[entry.key]!;
      for (final forbidden in entry.value) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '${entry.key} must not log financial payload details.',
        );
      }
    }
  });

  test('feature screens do not launch unvalidated URL strings directly', () {
    final sourceByPath = {
      'lib/features/common/presentation/screens/domain_accounting_records_screen.dart':
          File(
            'lib/features/common/presentation/screens/domain_accounting_records_screen.dart',
          ).readAsStringSync(),
      'lib/features/expenses/presentation/screens/expense_detail_screen.dart': File(
        'lib/features/expenses/presentation/screens/expense_detail_screen.dart',
      ).readAsStringSync(),
      'lib/features/payments/presentation/screens/payment_detail_screen.dart': File(
        'lib/features/payments/presentation/screens/payment_detail_screen.dart',
      ).readAsStringSync(),
      'lib/features/settings/presentation/screens/settings_screen.dart': File(
        'lib/features/settings/presentation/screens/settings_screen.dart',
      ).readAsStringSync(),
      'lib/features/workers/presentation/screens/worker_detail_screen.dart': File(
        'lib/features/workers/presentation/screens/worker_detail_screen.dart',
      ).readAsStringSync(),
    };

    for (final entry in sourceByPath.entries) {
      expect(
        entry.value,
        isNot(contains('launchUrlString(')),
        reason: '${entry.key} should launch URLs through safe_external_url.',
      );
    }
  });
}
