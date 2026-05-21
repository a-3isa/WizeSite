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

    test(
      'monthly flow includes queued finance actions before sync completes',
      () async {
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
      },
    );

    test(
      'queued actions build fallback metrics when project metrics are missing',
      () async {
        final container = ProviderContainer(
          overrides: [
            reportProjectIdProvider.overrideWith((ref) => 'project_1'),
            reportBaseMetricsProvider.overrideWith((ref) => Stream.value(null)),
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
      },
    );

    test(
      'monthly flow applies queued expense, payment, and worker-entry edits',
      () async {
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
                  totalExpenses: 300,
                  totalIncome: 200,
                  net: -100,
                  categoryTotals: const {'materials': 100, 'labor': 200},
                  monthlyFlow: [
                    MonthlyFlowData(
                      month: DateTime.utc(2026, 3),
                      expenses: 100,
                      income: 200,
                    ),
                    MonthlyFlowData(
                      month: DateTime.utc(2026, 4),
                      expenses: 200,
                      income: 0,
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
                      date: DateTime.utc(2026, 3, 1),
                      notes: 'old',
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
                      amount: 200,
                      date: DateTime.utc(2026, 3, 1),
                      paymentMethod: 'cash',
                      notes: 'old',
                      isArchived: false,
                    ),
                  ],
                ),
              ),
            ),
            reportPendingActionsProvider.overrideWith(
              (ref) => Stream.value([
                OfflineAction(
                  id: 'expense_edit',
                  type: OfflineActionTypes.updateExpense,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'expenseId': 'expense_live',
                    'category': 'equipment',
                    'amount': 150,
                    'date': DateTime.utc(2026, 4, 5).toIso8601String(),
                    'notes': 'new expense',
                    'previousAmount': 100,
                    'previousDate': DateTime.utc(2026, 3, 1).toIso8601String(),
                    'previousCategory': 'materials',
                  },
                  createdAt: DateTime.utc(2026, 4, 5),
                ),
                OfflineAction(
                  id: 'payment_edit',
                  type: OfflineActionTypes.updatePayment,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'paymentId': 'payment_live',
                    'amount': 250,
                    'date': DateTime.utc(2026, 4, 6).toIso8601String(),
                    'paymentMethod': 'bank',
                    'notes': 'new payment',
                    'previousAmount': 200,
                    'previousDate': DateTime.utc(2026, 3, 1).toIso8601String(),
                  },
                  createdAt: DateTime.utc(2026, 4, 6),
                ),
                OfflineAction(
                  id: 'worker_entry_edit',
                  type: OfflineActionTypes.updateWorkerEntry,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'entryId': 'entry_live',
                    'daysWorked': 3,
                    'dailyWage': 100,
                    'date': DateTime.utc(2026, 3, 7).toIso8601String(),
                    'previousProjectId': 'project_1',
                    'previousTotalCost': 200,
                    'previousDate': DateTime.utc(2026, 4, 1).toIso8601String(),
                  },
                  createdAt: DateTime.utc(2026, 3, 7),
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
        final categories = container
            .read(expensesByCategoryProvider)
            .requireValue;
        final expenses = container.read(reportExpensesProvider).requireValue;
        final payments = container.read(reportPaymentsProvider).requireValue;

        expect(summary['totalExpenses'], 450);
        expect(summary['totalIncome'], 250);
        expect(flow.first.expenses, 300);
        expect(flow.first.income, 0);
        expect(flow.last.expenses, 150);
        expect(flow.last.income, 250);
        expect(categories['materials'], isNull);
        expect(categories['equipment'], 150);
        expect(categories['labor'], 300);
        expect(expenses.first.amount, 150);
        expect(expenses.first.notes, 'new expense');
        expect(payments.first.amount, 250);
        expect(payments.first.paymentMethod, 'bank');
      },
    );

    test(
      'recently synced create actions still bridge metrics updates',
      () async {
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
                  totalExpenses: 16570,
                  totalIncome: 22820,
                  net: 6250,
                  categoryTotals: const {'materials': 16570},
                  monthlyFlow: [
                    MonthlyFlowData(
                      month: DateTime.utc(2026, 5),
                      expenses: 16570,
                      income: 22820,
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
                  id: 'expense_synced',
                  type: OfflineActionTypes.createExpense,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'projectName': 'Tower A',
                    'category': 'materials',
                    'amount': 100,
                    'currency': 'EGP',
                    'date': DateTime.utc(2026, 5, 20).toIso8601String(),
                  },
                  createdAt: DateTime.utc(2026, 5, 20),
                  status: OfflineActionStatus.synced,
                  syncedAt: DateTime.utc(2026, 5, 20, 1),
                ),
                OfflineAction(
                  id: 'payment_synced',
                  type: OfflineActionTypes.createPayment,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'amount': 50,
                    'date': DateTime.utc(2026, 5, 20).toIso8601String(),
                    'paymentMethod': 'cash',
                  },
                  createdAt: DateTime.utc(2026, 5, 20),
                  status: OfflineActionStatus.synced,
                  syncedAt: DateTime.utc(2026, 5, 20, 1),
                ),
                OfflineAction(
                  id: 'worker_entry_synced',
                  type: OfflineActionTypes.createWorkerEntry,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'workerId': 'worker_1',
                    'daysWorked': 2,
                    'dailyWage': 75,
                    'date': DateTime.utc(2026, 5, 20).toIso8601String(),
                  },
                  createdAt: DateTime.utc(2026, 5, 20),
                  status: OfflineActionStatus.synced,
                  syncedAt: DateTime.utc(2026, 5, 20, 1),
                ),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(reportBaseMetricsProvider.future);
        await container.read(reportPendingActionsProvider.future);

        final summary = container.read(reportSummaryProvider).requireValue;

        expect(summary['totalExpenses'], 16820);
        expect(summary['totalIncome'], 22870);
        expect(summary['net'], 6050);
      },
    );

    test(
      'synced create actions are ignored after metrics reflect them',
      () async {
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
                  totalExpenses: 16670,
                  totalIncome: 22870,
                  net: 6200,
                  categoryTotals: const {'materials': 16670},
                  monthlyFlow: [
                    MonthlyFlowData(
                      month: DateTime.utc(2026, 5),
                      expenses: 16670,
                      income: 22870,
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
                  id: 'expense_synced',
                  type: OfflineActionTypes.createExpense,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'projectName': 'Tower A',
                    'category': 'materials',
                    'amount': 100,
                    'currency': 'EGP',
                    'date': DateTime.utc(2026, 5, 20).toIso8601String(),
                    'projectTotalExpensesBefore': 16570,
                  },
                  createdAt: DateTime.utc(2026, 5, 20),
                  status: OfflineActionStatus.synced,
                  syncedAt: DateTime.utc(2026, 5, 20, 1),
                ),
                OfflineAction(
                  id: 'payment_synced',
                  type: OfflineActionTypes.createPayment,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'amount': 50,
                    'date': DateTime.utc(2026, 5, 20).toIso8601String(),
                    'paymentMethod': 'cash',
                    'projectTotalPaymentsBefore': 22820,
                  },
                  createdAt: DateTime.utc(2026, 5, 20),
                  status: OfflineActionStatus.synced,
                  syncedAt: DateTime.utc(2026, 5, 20, 1),
                ),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(reportBaseMetricsProvider.future);
        await container.read(reportPendingActionsProvider.future);

        final summary = container.read(reportSummaryProvider).requireValue;

        expect(summary['totalExpenses'], 16670);
        expect(summary['totalIncome'], 22870);
        expect(summary['net'], 6200);
      },
    );

    test(
      'worker-entry project moves subtract from the previous project report',
      () async {
        final container = ProviderContainer(
          overrides: [
            reportProjectIdProvider.overrideWith((ref) => 'project_old'),
            reportBaseMetricsProvider.overrideWith(
              (ref) => Stream.value(
                ReportMetrics(
                  projectId: 'project_old',
                  projectName: 'Old Project',
                  status: 'active',
                  isArchived: false,
                  totalExpenses: 200,
                  totalIncome: 0,
                  net: -200,
                  categoryTotals: const {'labor': 200},
                  monthlyFlow: [
                    MonthlyFlowData(
                      month: DateTime.utc(2026, 4),
                      expenses: 200,
                      income: 0,
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
                  id: 'worker_entry_move',
                  type: OfflineActionTypes.updateWorkerEntry,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_new',
                    'entryId': 'entry_live',
                    'daysWorked': 3,
                    'dailyWage': 100,
                    'date': DateTime.utc(2026, 5, 7).toIso8601String(),
                    'previousProjectId': 'project_old',
                    'previousTotalCost': 200,
                    'previousDate': DateTime.utc(2026, 4, 1).toIso8601String(),
                  },
                  createdAt: DateTime.utc(2026, 5, 7),
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
        final categories = container
            .read(expensesByCategoryProvider)
            .requireValue;

        expect(summary['totalExpenses'], 0);
        expect(flow.first.expenses, 0);
        expect(categories['labor'], isNull);
      },
    );
  });
}
