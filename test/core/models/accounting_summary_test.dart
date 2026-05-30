import 'package:buildtrack_app/core/models/accounting_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entity summary parses totals, breakdowns, and dates', () {
    final summary = EntityAccountingSummary.fromMap({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'entityId': 'entity_1',
      'entityName': 'Acme Materials',
      'entityType': 'supplier',
      'totalExpenses': 1200,
      'totalPayments': 500,
      'totalPaid': 500,
      'remainingBalance': 700,
      'transactionCount': 4,
      'attachmentCount': 2,
      'latestTransactionDate': '2026-05-27T00:00:00.000Z',
      'categoryBreakdown': {'materials': 1200},
      'paymentMethodBreakdown': {'cash': 500},
      'updatedAt': '2026-05-27T01:00:00.000Z',
    });

    expect(summary.entityName, 'Acme Materials');
    expect(summary.totalExpenses, 1200);
    expect(summary.remainingBalance, 700);
    expect(summary.categoryBreakdown['materials'], 1200);
    expect(summary.paymentMethodBreakdown['cash'], 500);
    expect(summary.toMap()['attachmentCount'], 2);
  });

  test('weekly summary requires bounded week dates', () {
    final summary = WeeklyAccountingSummary.fromMap({
      'workspaceId': 'workspace_1',
      'weekStart': '2026-05-25T00:00:00.000Z',
      'weekEnd': '2026-05-31T23:59:59.000Z',
      'totalExpenses': 3000,
      'totalPayments': 900,
      'topEntity': {'id': 'entity_1', 'name': 'Acme'},
      'topCategory': {'category': 'materials', 'total': 2000},
      'laborSummary': {'total': 500},
      'equipmentSummary': {'total': 250},
      'paymentSummary': {'cash': 900},
      'recentTransactionRefs': ['expense_1', 'payment_1'],
      'updatedAt': '2026-05-27T01:00:00.000Z',
    });

    expect(summary.weekStart.isBefore(summary.weekEnd), isTrue);
    expect(summary.totalExpenses, 3000);
    expect(summary.recentTransactionRefs, ['expense_1', 'payment_1']);
    expect(summary.toMap()['weekEnd'], isA<String>());
  });

  test('project and category summaries serialize compact totals', () {
    final project = ProjectAccountingSummary.fromMap({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'todayExpenses': 100,
      'weeklyExpenses': 700,
      'monthlyExpenses': 2500,
      'transactionCount': 12,
      'totalPayments': 900,
      'attachmentCount': 3,
      'updatedAt': '2026-05-27T01:00:00.000Z',
    });
    final category = CategoryAccountingSummary.fromMap({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'category': 'labor',
      'totalAmount': 450,
      'transactionCount': 3,
      'latestTransactionDate': '2026-05-27T00:00:00.000Z',
      'updatedAt': '2026-05-27T01:00:00.000Z',
    });

    expect(project.monthlyExpenses, 2500);
    expect(project.toMap()['transactionCount'], 12);
    expect(category.category, 'labor');
    expect(category.toMap()['totalAmount'], 450);
  });
}
