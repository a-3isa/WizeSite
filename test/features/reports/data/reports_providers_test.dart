import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('report providers', () {
    test('report summary includes queued expense and payment deltas', () async {
      final container = ProviderContainer(
        overrides: [
          reportProjectIdProvider.overrideWith((ref) => 'project_1'),
          reportBaseMetricsProvider.overrideWith(
            (ref) => Stream.value(
              ReportMetrics(
                projectId: 'project_1',
                projectName: 'Tower A',
                status: 'active',
                isArchived: false,
                totalExpenses: 100,
                totalIncome: 250,
                net: 150,
                categoryTotals: const {'materials': 100},
                monthlyFlow: [
                  MonthlyFlowData(
                    month: DateTime.utc(2026, 5),
                    expenses: 100,
                    income: 250,
                  ),
                ],
                topWorkers: const [],
                recentExpenses: const [],
                recentPayments: const [],
              ),
            ),
          ),
          reportPendingActionsProvider.overrideWith(
            (ref) => Stream.value([
              OfflineAction(
                id: 'payment_1',
                type: OfflineActionTypes.createPayment,
                payload: {
                  'workspaceId': 'workspace_1',
                  'projectId': 'project_1',
                  'amount': 80,
                  'date': DateTime.utc(2026, 5, 14).toIso8601String(),
                  'paymentMethod': 'cash',
                  'notes': 'Pending payment',
                },
                createdAt: DateTime.utc(2026, 5, 14),
              ),
              OfflineAction(
                id: 'expense_1',
                type: OfflineActionTypes.createExpense,
                payload: {
                  'workspaceId': 'workspace_1',
                  'projectId': 'project_1',
                  'projectName': 'Tower A',
                  'category': 'materials',
                  'amount': 40,
                  'currency': 'EGP',
                  'date': DateTime.utc(2026, 5, 13).toIso8601String(),
                  'notes': 'Pending expense',
                },
                createdAt: DateTime.utc(2026, 5, 13),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(reportBaseMetricsProvider.future);
      await container.read(reportPendingActionsProvider.future);

      final summary = container.read(reportSummaryProvider).requireValue;
      final metrics = container.read(reportMetricsProvider).requireValue;

      expect(summary['totalExpenses'], 140);
      expect(summary['totalIncome'], 330);
      expect(summary['net'], 190);
      expect(metrics?.recentExpenses.first.id, 'pending_expense_1');
      expect(metrics?.recentPayments.first.id, 'pending_payment_1');
    });

    test('monthly flow includes queued finance actions before sync completes', () async {
      final container = ProviderContainer(
        overrides: [
          reportProjectIdProvider.overrideWith((ref) => 'project_1'),
          reportBaseMetricsProvider.overrideWith(
            (ref) => Stream.value(
              ReportMetrics(
                projectId: 'project_1',
                projectName: 'Tower A',
                status: 'active',
                isArchived: false,
                totalExpenses: 100,
                totalIncome: 250,
                net: 150,
                categoryTotals: const {'materials': 100},
                monthlyFlow: [
                  MonthlyFlowData(
                    month: DateTime.utc(2026, 4),
                    expenses: 0,
                    income: 0,
                  ),
                  MonthlyFlowData(
                    month: DateTime.utc(2026, 5),
                    expenses: 100,
                    income: 250,
                  ),
                ],
                topWorkers: const [],
                recentExpenses: [
                  Expense(
                    id: 'expense_live',
                    workspaceId: 'workspace_1',
                    projectId: 'project_1',
                    projectName: 'Tower A',
                    category: 'materials',
                    amount: 100,
                    currency: 'EGP',
                    date: DateTime.utc(2026, 5, 1),
                    notes: '',
                    supplierName: '',
                    paymentMethod: '',
                    inputMethod: 'manual',
                    transcript: '',
                    source: '',
                    storagePath: '',
                    isArchived: false,
                  ),
                ],
                recentPayments: [
                  PaymentRecord(
                    id: 'payment_live',
                    workspaceId: 'workspace_1',
                    projectId: 'project_1',
                    amount: 250,
                    date: DateTime.utc(2026, 5, 1),
                    paymentMethod: 'cash',
                    notes: '',
                    isArchived: false,
                  ),
                ],
              ),
            ),
          ),
          reportPendingActionsProvider.overrideWith(
            (ref) => Stream.value([
              OfflineAction(
                id: 'payment_1',
                type: OfflineActionTypes.createPayment,
                payload: {
                  'workspaceId': 'workspace_1',
                  'projectId': 'project_1',
                  'amount': 80,
                  'date': DateTime.utc(2026, 4, 10).toIso8601String(),
                  'paymentMethod': 'cash',
                },
                createdAt: DateTime.utc(2026, 4, 10),
              ),
              OfflineAction(
                id: 'expense_1',
                type: OfflineActionTypes.createExpense,
                payload: {
                  'workspaceId': 'workspace_1',
                  'projectId': 'project_1',
                  'projectName': 'Tower A',
                  'category': 'materials',
                  'amount': 40,
                  'currency': 'EGP',
                  'date': DateTime.utc(2026, 4, 12).toIso8601String(),
                },
                createdAt: DateTime.utc(2026, 4, 12),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(reportBaseMetricsProvider.future);
      await container.read(reportPendingActionsProvider.future);

      final flow = container.read(monthlyFlowProvider).requireValue;

      expect(flow[0].expenses, 40);
      expect(flow[0].income, 80);
      expect(flow[1].expenses, 100);
      expect(flow[1].income, 250);
    });

    test('queued actions build fallback metrics when project metrics are missing', () async {
      final container = ProviderContainer(
        overrides: [
          reportProjectIdProvider.overrideWith((ref) => 'project_1'),
          reportBaseMetricsProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          reportPendingActionsProvider.overrideWith(
            (ref) => Stream.value([
              OfflineAction(
                id: 'payment_only_queue',
                type: OfflineActionTypes.createPayment,
                payload: {
                  'workspaceId': 'workspace_1',
                  'projectId': 'project_1',
                  'amount': 80,
                  'date': DateTime.utc(2026, 4, 10).toIso8601String(),
                  'paymentMethod': 'cash',
                  'notes': 'Queued payment',
                },
                createdAt: DateTime.utc(2026, 4, 10),
              ),
              OfflineAction(
                id: 'expense_only_queue',
                type: OfflineActionTypes.createExpense,
                payload: {
                  'workspaceId': 'workspace_1',
                  'projectId': 'project_1',
                  'projectName': 'Queued Project',
                  'category': 'materials',
                  'amount': 40,
                  'currency': 'EGP',
                  'date': DateTime.utc(2026, 4, 12).toIso8601String(),
                  'notes': 'Queued expense',
                },
                createdAt: DateTime.utc(2026, 4, 12),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(reportBaseMetricsProvider.future);
      await container.read(reportPendingActionsProvider.future);

      final summary = container.read(reportSummaryProvider).requireValue;
      final flow = container.read(monthlyFlowProvider).requireValue;

      expect(summary['totalExpenses'], 40);
      expect(summary['totalIncome'], 80);
      expect(summary['net'], 40);
      expect(flow, isNotEmpty);
      expect(flow.first.expenses, 40);
      expect(flow.first.income, 80);
    });
  });
}
