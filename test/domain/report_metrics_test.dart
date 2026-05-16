import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('financial metric normalization', () {
    test('ReportMetrics falls back to totalPayments and netProfit fields', () {
      final metrics = ReportMetrics.fromMap('project_1', {
        'projectName': 'Tower A',
        'status': 'active',
        'isArchived': false,
        'totalExpenses': 250,
        'totalPayments': 700,
        'netProfit': 450,
      });

      expect(metrics.totalExpenses, 250);
      expect(metrics.totalIncome, 700);
      expect(metrics.net, 450);
    });

    test('ReportMetrics derives net when no explicit net field exists', () {
      final metrics = ReportMetrics.fromMap('project_1', {
        'totalExpenses': 1200,
        'totalIncome': 2000,
      });

      expect(metrics.net, 800);
    });

    test(
      'Project derives totalPayments and netProfit from compatible fields',
      () {
        final project = Project.fromMap('project_1', {
          'workspaceId': 'workspace_1',
          'name': 'Tower A',
          'clientName': 'Client',
          'contractValue': 10000,
          'status': 'active',
          'completionPercentage': 30,
          'totalExpenses': 3000,
          'totalIncome': 5000,
          'net': 2000,
          'isArchived': false,
        });

        expect(project.totalPayments, 5000);
        expect(project.netProfit, 2000);
      },
    );
  });
}
