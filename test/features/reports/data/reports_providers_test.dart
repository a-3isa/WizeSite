import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/models/accounting_access_role.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/domain/report_scope.dart';
import 'package:buildtrack_app/features/reports/data/report_project_selector_provider.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockExpenseRepository extends Mock implements ExpenseRepository {}

class _MockPaymentRepository extends Mock implements PaymentRepository {}

Future<T> _readStreamProvider<T>(
  ProviderContainer container,
  StreamProvider<T> provider,
) {
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container.read(provider.future);
}

void main() {
  group('report providers', () {
    test('report scope defaults to month-to-date', () {
      final now = DateTime(2026, 6, 15, 14, 30);
      final scope = ReportScope.monthToDate(projectId: 'project_1', now: now);

      expect(scope.projectId, 'project_1');
      expect(scope.startDate, DateTime(2026, 6));
      expect(scope.endDate, DateTime(2026, 6, 15, 23, 59, 59, 999));
      expect(scope.contains(DateTime(2026, 6, 1)), isTrue);
      expect(scope.contains(DateTime(2026, 5, 31, 23, 59)), isFalse);
      expect(scope.copyWith(projectId: null).projectId, isNull);
    });

    test('effective scope keeps legacy project selection during migration', () {
      final container = ProviderContainer(
        overrides: [
          reportNowProvider.overrideWithValue(DateTime(2026, 6, 15)),
          reportProjectIdProvider.overrideWith((ref) => 'project_1'),
        ],
      );
      addTearDown(container.dispose);

      final scope = container.read(effectiveReportScopeProvider);

      expect(scope.projectId, 'project_1');
      expect(scope.startDate, DateTime(2026, 6));
    });

    test('report project selector can page archived projects', () async {
      final active = Project(
        id: 'active_1',
        workspaceId: 'workspace_1',
        name: 'Active',
        clientName: 'Client',
        contractValue: 100,
        status: 'active',
        completionPercentage: 10,
        totalExpenses: 0,
        totalPayments: 0,
        netProfit: 0,
        isArchived: false,
      );
      final archived = Project(
        id: 'archived_1',
        workspaceId: 'workspace_1',
        name: 'Archived',
        clientName: 'Client',
        contractValue: 100,
        status: 'completed',
        completionPercentage: 100,
        totalExpenses: 0,
        totalPayments: 0,
        netProfit: 0,
        isArchived: true,
      );
      final controller = ReportProjectSelectorController(
        loadActivePage: ({cursor}) async =>
            FirestorePage<Project>(items: [active], hasMore: false),
        loadArchivedPage: ({cursor}) async =>
            FirestorePage<Project>(items: [archived], hasMore: false),
      );

      await controller.loadInitial();
      expect(controller.state.projects.map((item) => item.id), ['active_1']);

      await controller.showArchived(true);
      expect(controller.state.projects.map((item) => item.id), ['archived_1']);
      expect(controller.state.showingArchived, isTrue);
    });

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

      await _readStreamProvider(container, reportBaseMetricsProvider);
      await _readStreamProvider(container, reportPendingActionsProvider);

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
                      attachments: const [],
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
                      attachments: const [],
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

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

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

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

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
                      attachments: const [],
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
                      attachments: const [],
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

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

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
        expect(categories['worker'], 300);
        expect(categories['labor'], isNull);
        expect(expenses.first.amount, 150);
        expect(expenses.first.notes, 'new expense');
        expect(payments.first.amount, 250);
        expect(payments.first.paymentMethod, 'bank');
      },
    );

    test(
      'queued worker entries merge into the server worker category',
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
                  totalIncome: 0,
                  net: -300,
                  // Server recompute now keys labor cost as 'worker'.
                  categoryTotals: const {'materials': 100, 'worker': 200},
                  monthlyFlow: const [],
                  topWorkers: const [],
                  recentExpenses: const [],
                  recentPayments: const [],
                ),
              ),
            ),
            reportPendingActionsProvider.overrideWith(
              (ref) => Stream.value([
                OfflineAction(
                  id: 'worker_entry_queued',
                  type: OfflineActionTypes.createWorkerEntry,
                  payload: {
                    'workspaceId': 'workspace_1',
                    'projectId': 'project_1',
                    'workerId': 'worker_1',
                    'daysWorked': 1,
                    'dailyWage': 50,
                    'date': DateTime.utc(2026, 5, 20).toIso8601String(),
                  },
                  createdAt: DateTime.utc(2026, 5, 20),
                ),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

        final categories = container
            .read(expensesByCategoryProvider)
            .requireValue;

        expect(categories['worker'], 250);
        expect(categories['labor'], isNull);
        expect(categories['materials'], 100);
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

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

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

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

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

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

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

    test(
      'domain accounting report providers return bounded project records',
      () async {
        final firestore = FakeFirebaseFirestore();
        final firstDate = DateTime.utc(2026, 6, 10);
        final secondDate = DateTime.utc(2026, 6, 9);
        await firestore.collection('worker_accounting_records').doc('w1').set({
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'workerId': 'worker_1',
          'workerName': 'Sam',
          'description': 'Wages',
          'amount': 120,
          'date': firstDate,
          'paymentMethod': 'cash',
          'paymentStatus': 'paid',
        });
        await firestore
            .collection('contractor_accounting_records')
            .doc('c1')
            .set({
              'workspaceId': 'workspace_1',
              'projectId': 'project_1',
              'contractorId': 'contractor_1',
              'contractorName': 'Mina Contracting',
              'description': 'Concrete work',
              'amount': 500,
              'date': firstDate,
              'paymentMethod': 'bank',
              'paymentStatus': 'pending',
            });
        await firestore
            .collection('equipment_accounting_records')
            .doc('e1')
            .set({
              'workspaceId': 'workspace_1',
              'projectId': 'project_1',
              'providerId': 'equipment_1',
              'providerName': 'Lift Rentals',
              'description': 'Crane rental',
              'amount': 300,
              'date': secondDate,
              'paymentMethod': 'cash',
              'paymentStatus': 'paid',
            });
        await firestore
            .collection('transport_provider_accounting_records')
            .doc('t1')
            .set({
              'workspaceId': 'workspace_1',
              'projectId': 'project_1',
              'providerId': 'transport_1',
              'providerName': 'Fast Trucks',
              'description': 'Material delivery',
              'amount': 80,
              'date': secondDate,
              'paymentMethod': 'cash',
              'paymentStatus': 'paid',
            });
        await firestore.collection('worker_accounting_records').doc('w2').set({
          'workspaceId': 'workspace_1',
          'projectId': 'other_project',
          'workerId': 'worker_2',
          'workerName': 'Other',
          'description': 'Other project',
          'amount': 999,
          'date': firstDate,
          'paymentMethod': 'cash',
          'paymentStatus': 'paid',
        });
        await firestore
            .collection('worker_accounting_records')
            .doc('w_old')
            .set({
              'workspaceId': 'workspace_1',
              'projectId': 'project_1',
              'workerId': 'worker_old',
              'workerName': 'Old Worker',
              'description': 'Outside scope',
              'amount': 777,
              'date': DateTime.utc(2026, 5, 31),
              'paymentMethod': 'cash',
              'paymentStatus': 'paid',
            });

        final container = ProviderContainer(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            reportProjectIdProvider.overrideWith((ref) => 'project_1'),
            // Pin the report clock inside the seeded June 2026 window so the
            // default month-to-date scope stays stable as real time advances.
            reportNowProvider.overrideWithValue(DateTime(2026, 6, 15)),
            currentAccountingRoleProvider.overrideWithValue(
              const AsyncData(AccountingAccessRoleType.owner),
            ),
          ],
        );
        addTearDown(container.dispose);

        final workers = await _readStreamProvider(
          container,
          reportWorkerAccountingRecordsProvider,
        );
        final contractors = await _readStreamProvider(
          container,
          reportContractorAccountingRecordsProvider,
        );
        final equipment = await _readStreamProvider(
          container,
          reportEquipmentAccountingRecordsProvider,
        );
        final transport = await _readStreamProvider(
          container,
          reportTransportAccountingRecordsProvider,
        );
        final topWorkers = container.read(topWorkersProvider).requireValue;

        expect(workers.map((item) => item.id), ['w1']);
        expect(topWorkers.single.name, 'Sam');
        expect(topWorkers.single.totalCost, 120);
        expect(contractors.single.contractorName, 'Mina Contracting');
        expect(equipment.single.providerName, 'Lift Rentals');
        expect(transport.single.providerName, 'Fast Trucks');
      },
    );

    test(
      'one project and date scope drives metrics categories flow and tables',
      () async {
        final expenses = _MockExpenseRepository();
        final payments = _MockPaymentRepository();
        final start = DateTime.utc(2026, 6, 1);
        final end = DateTime.utc(2026, 6, 15, 23, 59, 59, 999);
        final inScopeExpense = Expense(
          id: 'expense_in',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          projectName: 'Tower A',
          category: 'materials',
          amount: 120,
          currency: 'EGP',
          date: DateTime.utc(2026, 6, 10),
          notes: '',
          supplierName: '',
          paymentMethod: 'cash',
          inputMethod: 'manual',
          transcript: '',
          source: '',
          storagePath: '',
          attachments: const [],
          isArchived: false,
        );
        final wrongProjectExpense = Expense(
          id: 'expense_other',
          workspaceId: 'workspace_1',
          projectId: 'project_2',
          projectName: 'Tower B',
          category: 'equipment',
          amount: 900,
          currency: 'EGP',
          date: DateTime.utc(2026, 6, 11),
          notes: '',
          supplierName: '',
          paymentMethod: 'cash',
          inputMethod: 'manual',
          transcript: '',
          source: '',
          storagePath: '',
          attachments: const [],
          isArchived: false,
        );
        final oldExpense = Expense(
          id: 'expense_old',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          projectName: 'Tower A',
          category: 'labor',
          amount: 500,
          currency: 'EGP',
          date: DateTime.utc(2026, 5, 31),
          notes: '',
          supplierName: '',
          paymentMethod: 'cash',
          inputMethod: 'manual',
          transcript: '',
          source: '',
          storagePath: '',
          attachments: const [],
          isArchived: false,
        );
        final inScopePayment = PaymentRecord(
          id: 'payment_in',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          amount: 300,
          date: DateTime.utc(2026, 6, 12),
          paymentMethod: 'bank',
          notes: '',
          attachments: const [],
          isArchived: false,
        );
        final latePayment = PaymentRecord(
          id: 'payment_late',
          workspaceId: 'workspace_1',
          projectId: 'project_1',
          amount: 700,
          date: DateTime.utc(2026, 6, 16),
          paymentMethod: 'bank',
          notes: '',
          attachments: const [],
          isArchived: false,
        );
        when(
          () => expenses.fetchExpensesPage(
            'workspace_1',
            projectId: 'project_1',
            startDate: start,
            endDate: end,
            cursor: null,
            pageSize: 500,
          ),
        ).thenAnswer(
          (_) async => FirestorePage(
            items: [inScopeExpense, wrongProjectExpense, oldExpense],
            hasMore: false,
          ),
        );
        when(
          () => payments.fetchPaymentsPage(
            'workspace_1',
            projectId: 'project_1',
            startDate: start,
            endDate: end,
            cursor: null,
            pageSize: 500,
          ),
        ).thenAnswer(
          (_) async => FirestorePage(
            items: [inScopePayment, latePayment],
            hasMore: false,
          ),
        );

        final container = ProviderContainer(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            currentAccountingRoleProvider.overrideWithValue(
              const AsyncData(AccountingAccessRoleType.owner),
            ),
            reportScopeProvider.overrideWith(
              (ref) => ReportScope(
                projectId: 'project_1',
                startDate: start,
                endDate: end,
              ),
            ),
            expenseRepositoryProvider.overrideWithValue(expenses),
            paymentRepositoryProvider.overrideWithValue(payments),
            reportBaseMetricsProvider.overrideWith(
              (ref) => Stream.value(
                const ReportMetrics(
                  projectId: 'project_1',
                  projectName: 'Tower A',
                  status: 'active',
                  isArchived: false,
                  totalExpenses: 999,
                  totalIncome: 999,
                  net: 0,
                  categoryTotals: {},
                  monthlyFlow: [],
                  topWorkers: [],
                  recentExpenses: [],
                  recentPayments: [],
                ),
              ),
            ),
            reportPendingActionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(reportScopedRowsProvider.future);
        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

        final metrics = container.read(reportMetricsProvider).requireValue!;
        expect(metrics.totalExpenses, 120);
        expect(metrics.totalIncome, 300);
        expect(metrics.net, 180);
        expect(metrics.recentExpenses.map((item) => item.id), ['expense_in']);
        expect(metrics.recentPayments.map((item) => item.id), ['payment_in']);
        expect(container.read(expensesByCategoryProvider).requireValue, {
          'materials': 120,
        });
        expect(
          container.read(monthlyFlowProvider).requireValue.single.expenses,
          120,
        );
        expect(container.read(reportSummaryProvider).requireValue['net'], 180);
      },
    );

    test('scoped report income ignores unpaid payments', () async {
      final expenses = _MockExpenseRepository();
      final payments = _MockPaymentRepository();
      final start = DateTime.utc(2026, 6);
      final end = DateTime.utc(2026, 6, 15, 23, 59, 59, 999);
      final unpaid = PaymentRecord(
        id: 'payment_unpaid',
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        amount: 10000,
        date: DateTime.utc(2026, 6, 12),
        paymentMethod: 'bank',
        paymentStatus: 'unpaid',
        notes: '',
        attachments: const [],
        isArchived: false,
      );
      when(
        () => expenses.fetchExpensesPage(
          'workspace_1',
          projectId: 'project_1',
          startDate: start,
          endDate: end,
          cursor: null,
          pageSize: 500,
        ),
      ).thenAnswer(
        (_) async => const FirestorePage(items: [], hasMore: false),
      );
      when(
        () => payments.fetchPaymentsPage(
          'workspace_1',
          projectId: 'project_1',
          startDate: start,
          endDate: end,
          cursor: null,
          pageSize: 500,
        ),
      ).thenAnswer(
        (_) async => FirestorePage(items: [unpaid], hasMore: false),
      );

      final container = ProviderContainer(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          currentAccountingRoleProvider.overrideWithValue(
            const AsyncData(AccountingAccessRoleType.owner),
          ),
          reportScopeProvider.overrideWith(
            (ref) => ReportScope(
              projectId: 'project_1',
              startDate: start,
              endDate: end,
            ),
          ),
          expenseRepositoryProvider.overrideWithValue(expenses),
          paymentRepositoryProvider.overrideWithValue(payments),
          reportBaseMetricsProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          reportPendingActionsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(reportScopedRowsProvider.future);
      await _readStreamProvider(container, reportBaseMetricsProvider);
      await _readStreamProvider(container, reportPendingActionsProvider);

      final metrics = container.read(reportMetricsProvider).requireValue!;
      expect(metrics.totalIncome, 0);
      expect(metrics.net, 0);
    });

    test('denied roles short-circuit report data reads', () async {
      final expenses = _MockExpenseRepository();
      final payments = _MockPaymentRepository();
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('project_metrics').doc('project_1').set({
        'projectId': 'project_1',
        'totalExpenses': 100,
      });
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          currentAccountingRoleProvider.overrideWithValue(
            const AsyncData(AccountingAccessRoleType.member),
          ),
          reportScopeProvider.overrideWith(
            (ref) => ReportScope.monthToDate(
              projectId: 'project_1',
              now: DateTime.utc(2026, 6, 15),
            ),
          ),
          expenseRepositoryProvider.overrideWithValue(expenses),
          paymentRepositoryProvider.overrideWithValue(payments),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(reportScopedRowsProvider.future), isNull);
      expect(
        await _readStreamProvider(container, reportBaseMetricsProvider),
        isNull,
      );
      expect(
        await _readStreamProvider(
          container,
          reportWorkerAccountingRecordsProvider,
        ),
        isEmpty,
      );
      verifyNever(
        () => expenses.fetchExpensesPage(
          any(),
          projectId: any(named: 'projectId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      );
      verifyNever(
        () => payments.fetchPaymentsPage(
          any(),
          projectId: any(named: 'projectId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      );
    });

    test(
      'all-projects scope aggregates workspace rows across projects',
      () async {
        final firestore = FakeFirebaseFirestore();
        final start = DateTime.utc(2026, 6, 1);
        final end = DateTime.utc(2026, 6, 30, 23, 59, 59, 999);

        await firestore.collection('expenses').doc('e1').set({
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'projectName': 'A',
          'category': 'materials',
          'amount': 100,
          'currency': 'EGP',
          'date': DateTime.utc(2026, 6, 5),
          'isArchived': false,
        });
        await firestore.collection('expenses').doc('e2').set({
          'workspaceId': 'workspace_1',
          'projectId': 'project_2',
          'projectName': 'B',
          'category': 'labor',
          'amount': 50,
          'currency': 'EGP',
          'date': DateTime.utc(2026, 6, 6),
          'isArchived': false,
        });
        // Archived row must be excluded.
        await firestore.collection('expenses').doc('e3').set({
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'category': 'materials',
          'amount': 999,
          'currency': 'EGP',
          'date': DateTime.utc(2026, 6, 7),
          'isArchived': true,
        });
        // Other workspace must be excluded.
        await firestore.collection('expenses').doc('e4').set({
          'workspaceId': 'workspace_2',
          'projectId': 'p',
          'category': 'materials',
          'amount': 777,
          'currency': 'EGP',
          'date': DateTime.utc(2026, 6, 8),
          'isArchived': false,
        });
        await firestore.collection('payments').doc('p1').set({
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'amount': 200,
          'date': DateTime.utc(2026, 6, 9),
          'paymentMethod': 'cash',
          'isArchived': false,
        });
        await firestore.collection('payments').doc('p2').set({
          'workspaceId': 'workspace_1',
          'projectId': 'project_2',
          'amount': 80,
          'date': DateTime.utc(2026, 6, 10),
          'paymentMethod': 'cash',
          'isArchived': false,
        });

        final container = ProviderContainer(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            currentAccountingRoleProvider.overrideWithValue(
              const AsyncData(AccountingAccessRoleType.owner),
            ),
            reportScopeProvider.overrideWith(
              (ref) => ReportScope(startDate: start, endDate: end),
            ),
            reportPendingActionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        );
        addTearDown(container.dispose);

        final rows = await container.read(reportScopedRowsProvider.future);
        expect(rows, isNotNull);
        expect(rows!.expenses.map((item) => item.id).toSet(), {'e1', 'e2'});
        expect(rows.payments.map((item) => item.id).toSet(), {'p1', 'p2'});

        await _readStreamProvider(container, reportBaseMetricsProvider);
        await _readStreamProvider(container, reportPendingActionsProvider);

        final summary = container.read(reportSummaryProvider).requireValue;
        expect(summary['totalExpenses'], 150);
        expect(summary['totalIncome'], 280);
        expect(summary['net'], 130);

        final categories = container
            .read(expensesByCategoryProvider)
            .requireValue;
        expect(categories['materials'], 100);
        expect(categories['labor'], 50);
      },
    );
  });
}
