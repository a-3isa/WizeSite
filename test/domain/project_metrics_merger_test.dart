import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeProjectMetricsData', () {
    test(
      'uses project_metrics totals as authoritative project finance fields',
      () {
        final merged = mergeProjectMetricsData(
          projectData: {
            'workspaceId': 'workspace_1',
            'name': 'Tower A',
            'clientName': 'Client',
            'contractValue': 10000,
            'totalExpenses': 0,
            'totalPayments': 0,
            'netProfit': 0,
          },
          metricsData: {
            'workspaceId': 'workspace_1',
            'totalExpenses': 2500,
            'totalIncome': 4000,
            'net': 1500,
          },
        );

        final project = Project.fromMap('project_1', merged);

        expect(project.totalExpenses, 2500);
        expect(project.totalPayments, 4000);
        expect(project.netProfit, 1500);
      },
    );

    test('ignores metrics from another workspace', () {
      final merged = mergeProjectMetricsData(
        projectData: {'workspaceId': 'workspace_1', 'totalExpenses': 100},
        metricsData: {'workspaceId': 'workspace_2', 'totalExpenses': 999},
      );

      expect(merged['totalExpenses'], 100);
    });
  });
}
