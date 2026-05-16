const _projectMetricFields = {
  'budgetExceeded',
  'categoryTotals',
  'expectedFinalCost',
  'healthStatus',
  'monthlyFlow',
  'net',
  'netProfit',
  'recentExpenses',
  'recentPayments',
  'remainingBalance',
  'riskLevel',
  'topWorkers',
  'totalExpenses',
  'totalIncome',
  'totalLaborCost',
  'totalPayments',
};

Map<String, dynamic> mergeProjectMetricsData({
  required Map<String, dynamic> projectData,
  Map<String, dynamic>? metricsData,
}) {
  final merged = Map<String, dynamic>.of(projectData);
  if (metricsData == null) {
    return merged;
  }

  final projectWorkspaceId = '${projectData['workspaceId'] ?? ''}'.trim();
  final metricWorkspaceId = '${metricsData['workspaceId'] ?? ''}'.trim();
  if (projectWorkspaceId.isNotEmpty &&
      metricWorkspaceId.isNotEmpty &&
      projectWorkspaceId != metricWorkspaceId) {
    return merged;
  }

  for (final field in _projectMetricFields) {
    if (metricsData.containsKey(field)) {
      merged[field] = metricsData[field];
    }
  }
  if (metricsData.containsKey('totalIncome') &&
      !metricsData.containsKey('totalPayments')) {
    merged['totalPayments'] = metricsData['totalIncome'];
  }
  if (metricsData.containsKey('net') && !metricsData.containsKey('netProfit')) {
    merged['netProfit'] = metricsData['net'];
  }
  return merged;
}
