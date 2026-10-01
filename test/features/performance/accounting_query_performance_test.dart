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

      // Local replica reads (spec 004): keyset pages of `pageSize` rows.
      for (final repository in [expenseRepository, paymentRepository]) {
        expect(repository, contains('ORDER BY date DESC, id DESC LIMIT ?'));
        expect(repository, contains('[...args, pageSize]'));
        expect(repository, contains('cursor as LocalPageCursor?'));
      }
    });

    test('weekly dashboard reads are date bounded on both sides', () {
      final dashboardProviders = File(
        'lib/features/dashboard/data/dashboard_providers.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r"'expenses',[\s\S]*?rangeFrom: startDate,[\s\S]*?rangeTo: endDate",
        ).hasMatch(dashboardProviders),
        isTrue,
      );
      expect(
        RegExp(
          r"'payments',[\s\S]*?rangeFrom: startDate,[\s\S]*?rangeTo: endDate",
        ).hasMatch(dashboardProviders),
        isTrue,
      );
    });

    test(
      'entity aggregation uses maintained summaries instead of raw scans',
      () {
        final entityProviders = File(
          'lib/features/reports/data/entity_aggregation_providers.dart',
        ).readAsStringSync();

        // Reads go through DocSource (spec 004): DocQuery('collection', ...).
        expect(entityProviders, contains("'entity_summaries',"));
        expect(entityProviders, contains('limit: 100'));
        expect(entityProviders, isNot(contains("'expenses',")));
        expect(entityProviders, isNot(contains("'payments',")));
      },
    );

    test('50-project financial pages sort globally in project metrics', () {
      final projectRepository = File(
        'lib/features/projects/data/project_repository.dart',
      ).readAsStringSync();

      // Local replica reads (spec 004): financial sorts rank on the
      // maintained metrics row, keyset-paged, in SQL.
      expect(projectRepository, contains('LEFT JOIN project_metrics m'));
      expect(
        projectRepository,
        contains(r"json_extract(m.payload, '\$.totalExpenses')"),
      );
      expect(projectRepository, contains('cursor as LocalPageCursor?'));
      expect(projectRepository, contains("'LIMIT ?'"));
      expect(projectRepository, contains('watchProjects(String workspaceId)'));
      expect(projectRepository, contains('maxResults: 50'));
    });

    test(
      'dashboard snapshot composes financial totals from one metrics doc',
      () {
        final dashboardProviders = File(
          'lib/features/dashboard/data/dashboard_providers.dart',
        ).readAsStringSync();
        final snapshotStream = dashboardProviders.substring(
          dashboardProviders.indexOf('Stream<DashboardSnapshot>'),
          dashboardProviders.indexOf('final dashboardSummaryProvider'),
        );

        expect(
          snapshotStream,
          contains("watchDoc('workspace_metrics', workspaceId)"),
        );
        expect(snapshotStream, isNot(contains("'project_metrics'")));
        expect(snapshotStream, isNot(contains("'projects'")));
        expect(snapshotStream, isNot(contains("'expenses'")));
        expect(snapshotStream, isNot(contains("'payments'")));
      },
    );

    test(
      '100-entity directories depend on post-backfill timestamp visibility',
      () {
        // Reads come from the local replica (spec 004); the orderings keep
        // Firestore's semantics (never-used entities excluded from "recent").
        final entityRepository = File(
          'lib/features/entities/data/local_entity_repository.dart',
        ).readAsStringSync();
        final backfill = File(
          'functions/src/entity_last_used_backfill.ts',
        ).readAsStringSync();

        expect(entityRepository, contains('last_used_at IS NOT NULL'));
        expect(entityRepository, contains('ORDER BY last_used_at DESC'));
        expect(entityRepository, contains('normalized_name'));
        expect(entityRepository, contains('LocalPageCursor'));
        expect(backfill, contains('data.lastUsedAt == null'));
        expect(backfill, contains('parseDate(data.createdAt)'));
        expect(backfill, contains('parseDate(data.updatedAt)'));
        expect(backfill, contains('new Date(0)'));
        expect(backfill, contains('.limit(batchSize)'));
        expect(backfill, contains('startAfter(startAfterId)'));
      },
    );

    test('2,000-expense and 1,000-payment exports loop beyond 500 rows', () {
      final exportBuilder = File(
        'lib/features/reports/services/report_export_data_builder.dart',
      ).readAsStringSync();

      expect(exportBuilder, contains('static const int pageSize = 500'));
      expect(
        exportBuilder,
        contains('Future<List<Expense>> _fetchAllExpenses'),
      );
      expect(
        exportBuilder,
        contains('Future<List<PaymentRecord>> _fetchAllPayments'),
      );
      expect(exportBuilder, contains('while (true)'));
      expect(exportBuilder, contains('fetchExpensesPage('));
      expect(exportBuilder, contains('fetchPaymentsPage('));
      expect(exportBuilder, contains('cursor = page.nextCursor'));
      expect(
        exportBuilder,
        contains('if (!page.hasMore || page.nextCursor == null)'),
      );
      expect(exportBuilder, contains('startDate: startDate'));
      expect(exportBuilder, contains('endDate: endDate'));
      expect(exportBuilder, contains('projectId: projectId'));
    });
  });
}
