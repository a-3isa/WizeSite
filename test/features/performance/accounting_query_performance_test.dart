import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accounting query performance guardrails', () {
    test('transaction list repositories keep paginated query limits', () {
      final expenseRepository = File(
        'lib/features/expenses/data/expense_repository.dart',
      ).readAsStringSync();
      final paymentRepository = File(
        'lib/features/payments/data/payment_repository.dart',
      ).readAsStringSync();

      expect(expenseRepository, contains(".limit(pageSize)"));
      expect(paymentRepository, contains(".limit(pageSize)"));
      expect(expenseRepository, contains("startAfterDocument"));
      expect(paymentRepository, contains("startAfterDocument"));
    });

    test('weekly dashboard reads are date bounded on both sides', () {
      final dashboardProviders = File(
        'lib/features/dashboard/data/dashboard_providers.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r"collection\('expenses'\)[\s\S]*?isGreaterThanOrEqualTo: startDate[\s\S]*?isLessThanOrEqualTo: endDate",
        ).hasMatch(dashboardProviders),
        isTrue,
      );
      expect(
        RegExp(
          r"collection\('payments'\)[\s\S]*?isGreaterThanOrEqualTo: startDate[\s\S]*?isLessThanOrEqualTo: endDate",
        ).hasMatch(dashboardProviders),
        isTrue,
      );
    });

    test('entity aggregation uses maintained summaries instead of raw scans', () {
      final entityProviders = File(
        'lib/features/reports/data/entity_aggregation_providers.dart',
      ).readAsStringSync();

      expect(entityProviders, contains("collection('entity_summaries')"));
      expect(entityProviders, contains('.limit(100)'));
      expect(entityProviders, isNot(contains("collection('expenses')")));
      expect(entityProviders, isNot(contains("collection('payments')")));
    });
  });
}
