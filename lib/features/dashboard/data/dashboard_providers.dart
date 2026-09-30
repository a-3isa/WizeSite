import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'dart:async';

import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/utils/cash_collected.dart';
import 'package:buildtrack_app/core/utils/expense_category.dart';
import 'package:buildtrack_app/core/utils/utc_calendar.dart';
import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardSnapshotProvider =
    StreamProvider.family<DashboardSnapshot, String>((ref, workspaceId) {
      final roleFuture = ref.watch(currentAccountingRoleProvider.future);
      final source = ref.watch(docSourceProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return Stream.fromFuture(roleFuture).asyncExpand((role) {
        if (role?.canAccessAccounting != true) {
          return Stream.value(DashboardSnapshot.restricted());
        }
        return _dashboardSnapshotStream(
          source: source,
          queue: queue,
          workspaceId: workspaceId,
        );
      });
    });

Stream<DashboardSnapshot> _dashboardSnapshotStream({
  required DocSource source,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final metricsStream = source.watchDoc('workspace_metrics', workspaceId);
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    Map<String, dynamic>? metrics;
    List<OfflineAction> actions = const [];

    void emit() {
      final data = metrics;
      if (data == null) return;
      final merged = Map<String, dynamic>.from(data);
      var pendingExpenses = 0.0;
      var pendingIncome = 0.0;
      for (final action in actions) {
        if (action.status == OfflineActionStatus.synced ||
            action.status == OfflineActionStatus.deadLetter ||
            '${action.payload['workspaceId'] ?? ''}' != workspaceId) {
          continue;
        }
        final amount = ((action.payload['amount'] as num?) ?? 0).toDouble();
        final previous = ((action.payload['previousAmount'] as num?) ?? 0)
            .toDouble();
        switch (action.type) {
          case OfflineActionTypes.createExpense:
            pendingExpenses += amount;
            break;
          case OfflineActionTypes.updateExpense:
            pendingExpenses += amount - previous;
            break;
          case OfflineActionTypes.archiveExpense:
            pendingExpenses -= amount;
            break;
          case OfflineActionTypes.createPayment:
            pendingIncome += _cashInFromMap(action.payload);
            break;
          case OfflineActionTypes.updatePayment:
            pendingIncome +=
                _cashInFromMap(action.payload) -
                cashCollectedAmount(
                  amount: previous,
                  paymentStatus:
                      (action.payload['previousPaymentStatus'] as String?) ??
                      (action.payload['paymentStatus'] as String?),
                  paidAmount: (action.payload['previousPaidAmount'] as num?)
                      ?.toDouble(),
                );
            break;
          case OfflineActionTypes.archivePayment:
            pendingIncome -= _cashInFromMap(action.payload);
            break;
          default:
            break;
        }
      }
      merged['totalExpenses'] =
          ((data['totalExpenses'] as num?) ?? 0).toDouble() + pendingExpenses;
      merged['totalIncome'] =
          ((data['totalIncome'] as num?) ?? 0).toDouble() + pendingIncome;
      controller.add(DashboardSnapshot.fromMap(merged));
    }

    final metricsSub = metricsStream.listen((snapshot) {
      metrics = snapshot?.data ?? const <String, dynamic>{};
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((next) {
      actions = next;
      emit();
    }, onError: controller.addError);
    controller.onCancel = () async {
      await metricsSub.cancel();
      await queueSub.cancel();
    };
  });
}

/// Identifies a single project within a workspace.
typedef ProjectScope = ({String workspaceId, String projectId});

/// Recent transactions (expenses + payments) for one project, newest first.
/// Powers the project-scoped dashboard's "Recent" list.
final projectRecentTransactionsProvider =
    StreamProvider.family<List<DashboardTransactionRef>, ProjectScope>((
      ref,
      scope,
    ) {
      final expenseRepo = ref.watch(expenseRepositoryProvider);
      final paymentRepo = ref.watch(paymentRepositoryProvider);
      final expensesStream = expenseRepo.watchExpenses(
        scope.workspaceId,
        scope.projectId,
      );
      final paymentsStream = paymentRepo.watchPayments(
        scope.workspaceId,
        projectId: scope.projectId,
      );

      return Stream.multi((controller) {
        List<Expense>? expenses;
        List<PaymentRecord>? payments;

        void emit() {
          if (expenses == null && payments == null) return;
          final items =
              <DashboardTransactionRef>[
                for (final e in expenses ?? const <Expense>[])
                  DashboardTransactionRef(
                    id: e.id,
                    type: 'expense',
                    title: e.entityName.isNotEmpty
                        ? e.entityName
                        : (e.supplierName.isNotEmpty
                              ? e.supplierName
                              : e.description),
                    amount: e.amount,
                    date: e.date,
                  ),
                for (final p in payments ?? const <PaymentRecord>[])
                  DashboardTransactionRef(
                    id: p.id,
                    type: 'payment',
                    title: p.entityName.isNotEmpty
                        ? p.entityName
                        : p.description,
                    amount: p.amount,
                    date: p.date,
                  ),
              ]..sort(
                (a, b) =>
                    (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
              );
          controller.add(items.take(6).toList(growable: false));
        }

        final expenseSub = expensesStream.listen((value) {
          expenses = value;
          emit();
        }, onError: controller.addError);
        final paymentSub = paymentsStream.listen((value) {
          payments = value;
          emit();
        }, onError: controller.addError);
        controller.onCancel = () async {
          await expenseSub.cancel();
          await paymentSub.cancel();
        };
      });
    });

final dashboardSummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) {
      final source = ref.watch(docSourceProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _projectsSummaryStream(
        source: source,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

final dashboardWeeklySummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) {
      final source = ref.watch(docSourceProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _weeklySummaryStream(
        source: source,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

final dashboardWeeklyInsightsProvider =
    StreamProvider.family<DashboardWeeklyInsights, String>((ref, workspaceId) {
      final source = ref.watch(docSourceProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _weeklyInsightsStream(
        source: source,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

class DashboardWeeklyInsights {
  DashboardWeeklyInsights({
    required this.topEntity,
    required this.topCategory,
    required this.laborTotal,
    required this.equipmentTotal,
    required this.paymentSummary,
    required this.recentTransactions,
  });

  final String topEntity;
  final String topCategory;
  final double laborTotal;
  final double equipmentTotal;
  final Map<String, double> paymentSummary;
  final List<WeeklyDashboardTransaction> recentTransactions;
}

class WeeklyDashboardTransaction {
  WeeklyDashboardTransaction({
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
  });

  final String title;
  final double amount;
  final DateTime date;
  final String type;
}

Stream<DashboardWeeklyInsights> _weeklyInsightsStream({
  required DocSource source,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final week = utcIsoWeekBounds();
  final startDate = week.start;
  final endDate = week.end;

  final expensesStream = source.watch(
    DocQuery(
      'expenses',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final paymentsStream = source.watch(
    DocQuery(
      'payments',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final workerEntriesStream = source.watch(
    DocQuery(
      'worker_entries',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    List<Doc>? latestExpenses;
    List<Doc>? latestPayments;
    List<Doc>? latestWorkerEntries;
    List<OfflineAction> latestActions = const [];

    void emit() {
      final expenses = latestExpenses ?? const [];
      final payments = latestPayments ?? const [];
      final workerEntries = latestWorkerEntries ?? const [];

      final categoryTotals = <String, double>{};
      final entityTotals = <String, double>{};
      var laborTotal = 0.0;
      var equipmentTotal = 0.0;
      final paymentTotals = <String, double>{};
      final recent = <WeeklyDashboardTransaction>[];

      DateTime? parseDate(dynamic date) {
        if (date is DateTime) return date;
        if (date is Timestamp) return date.toDate();
        if (date is String) return DateTime.tryParse(date);
        return null;
      }

      for (final doc in expenses) {
        final data = doc.data;
        final amount = ((data['amount'] as num?) ?? 0).toDouble();
        final category = normalizeExpenseCategory('${data['category'] ?? ''}');
        final entityName = _normalizedEntityName(
          data['entityName'] ?? data['supplierName'],
        );
        final paymentMethod = '${data['paymentMethod'] ?? 'Unknown'}'.trim();
        final date = parseDate(data['date']);

        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
        if (category == AccountingCategories.worker) {
          laborTotal += amount;
        }
        if (category == AccountingCategories.equipment) {
          equipmentTotal += amount;
        }
        paymentTotals[paymentMethod] =
            (paymentTotals[paymentMethod] ?? 0) + amount;

        if (date != null) {
          recent.add(
            WeeklyDashboardTransaction(
              title: entityName,
              amount: amount,
              date: date,
              type: 'expense',
            ),
          );
        }
      }

      for (final doc in payments) {
        final data = doc.data;
        final amount = ((data['amount'] as num?) ?? 0).toDouble();
        final entityName = _normalizedEntityName(
          data['entityName'] ?? data['supplierName'],
        );
        final paymentMethod = '${data['paymentMethod'] ?? 'Unknown'}'.trim();
        final date = parseDate(data['date']);

        entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
        paymentTotals[paymentMethod] =
            (paymentTotals[paymentMethod] ?? 0) + amount;

        if (date != null) {
          recent.add(
            WeeklyDashboardTransaction(
              title: entityName,
              amount: amount,
              date: date,
              type: 'payment',
            ),
          );
        }
      }

      for (final doc in workerEntries) {
        final data = doc.data;
        final amount = _workerEntryCost(data);
        final entityName = _normalizedEntityName(
          data['entityName'] ?? data['workerName'],
        );
        final date = parseDate(data['date']);
        categoryTotals[AccountingCategories.worker] =
            (categoryTotals[AccountingCategories.worker] ?? 0) + amount;
        entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
        laborTotal += amount;
        if (date != null) {
          recent.add(
            WeeklyDashboardTransaction(
              title: entityName,
              amount: amount,
              date: date,
              type: 'expense',
            ),
          );
        }
      }

      for (final action in latestActions) {
        if (!_shouldApplyPendingWeeklyAction(action)) {
          continue;
        }
        final payload = action.payload;
        final payloadWorkspaceId = '${payload['workspaceId'] ?? ''}';
        if (payloadWorkspaceId != workspaceId) continue;
        final actionDate = parseDate(payload['date']) ?? action.createdAt;
        if (actionDate.isBefore(startDate) || actionDate.isAfter(endDate)) {
          continue;
        }
        final amount = ((payload['amount'] as num?) ?? 0).toDouble();
        final category = normalizeExpenseCategory(
          '${payload['category'] ?? ''}',
        );
        final entityName = _normalizedEntityName(
          payload['entityName'] ?? payload['supplierName'],
        );
        final paymentMethod = '${payload['paymentMethod'] ?? 'Unknown'}'.trim();

        if (action.type == OfflineActionTypes.createExpense) {
          categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
          entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
          if (category == AccountingCategories.worker) {
            laborTotal += amount;
          }
          if (category == AccountingCategories.equipment) {
            equipmentTotal += amount;
          }
          paymentTotals[paymentMethod] =
              (paymentTotals[paymentMethod] ?? 0) + amount;
          recent.add(
            WeeklyDashboardTransaction(
              title: entityName,
              amount: amount,
              date: actionDate,
              type: 'expense',
            ),
          );
        } else if (action.type == OfflineActionTypes.createPayment) {
          entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
          paymentTotals[paymentMethod] =
              (paymentTotals[paymentMethod] ?? 0) + amount;
          recent.add(
            WeeklyDashboardTransaction(
              title: entityName,
              amount: amount,
              date: actionDate,
              type: 'payment',
            ),
          );
        } else if (action.type == OfflineActionTypes.createWorkerEntry) {
          final cost = _workerEntryCost(payload);
          final workerName = _normalizedEntityName(
            payload['entityName'] ?? payload['workerName'],
          );
          categoryTotals[AccountingCategories.worker] =
              (categoryTotals[AccountingCategories.worker] ?? 0) + cost;
          entityTotals[workerName] = (entityTotals[workerName] ?? 0) + cost;
          laborTotal += cost;
          recent.add(
            WeeklyDashboardTransaction(
              title: workerName,
              amount: cost,
              date: actionDate,
              type: 'expense',
            ),
          );
        }
      }

      final topCategory = categoryTotals.entries.toList().fold<String>(
        'unassigned',
        (previous, entry) {
          if (previous == 'unassigned') {
            return entry.key.isEmpty ? previous : entry.key;
          }
          return (categoryTotals[previous] ?? 0) >= entry.value
              ? previous
              : entry.key;
        },
      );
      final topEntity = entityTotals.entries.toList().fold<String>(
        'unassigned',
        (previous, entry) {
          if (previous == 'unassigned') {
            return entry.key.isEmpty ? previous : entry.key;
          }
          return (entityTotals[previous] ?? 0) >= entry.value
              ? previous
              : entry.key;
        },
      );

      recent.sort((a, b) => b.date.compareTo(a.date));
      final recentList = recent.take(5).toList(growable: false);

      controller.add(
        DashboardWeeklyInsights(
          topEntity: topEntity,
          topCategory: topCategory,
          laborTotal: laborTotal,
          equipmentTotal: equipmentTotal,
          paymentSummary: paymentTotals,
          recentTransactions: recentList,
        ),
      );
    }

    final expenseSub = expensesStream.listen((snapshot) {
      latestExpenses = snapshot;
      emit();
    }, onError: controller.addError);
    final paymentSub = paymentsStream.listen((snapshot) {
      latestPayments = snapshot;
      emit();
    }, onError: controller.addError);
    final workerEntrySub = workerEntriesStream.listen((snapshot) {
      latestWorkerEntries = snapshot;
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await expenseSub.cancel();
      await paymentSub.cancel();
      await workerEntrySub.cancel();
      await queueSub.cancel();
    };
  });
}

String _normalizedEntityName(Object? value) {
  if (value == null) {
    return 'unassigned';
  }
  final name = '$value'.trim();
  return name.isEmpty ? 'unassigned' : name;
}

Stream<Map<String, num>> _projectsSummaryStream({
  required DocSource source,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final projectsStream = source.watch(
    DocQuery(
      'projects',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
    ),
  );
  // Cap keeps the all-projects overview correct for typical workspaces.
  final metricsStream = source.watch(
    DocQuery(
      'project_metrics',
      equals: {'workspaceId': workspaceId},
      limit: 200,
    ),
  );

  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    List<Doc>? latestProjects;
    List<Doc>? latestMetrics;
    List<OfflineAction> latestActions = const [];

    void emit() {
      const emptyDocs = <Doc>[];
      final projects = latestProjects ?? emptyDocs;
      final metricsByProjectId = {
        for (final doc in latestMetrics ?? emptyDocs) doc.id: doc.data,
      };
      num totalExpenses = 0;
      num totalIncome = 0;
      num totalNet = 0;
      var activeProjects = 0;
      final expensesByProjectId = <String, double>{};
      final incomeByProjectId = <String, double>{};

      for (final doc in projects) {
        final data = mergeProjectMetricsData(
          projectData: doc.data,
          metricsData: metricsByProjectId[doc.id],
        );
        final expenses = (data['totalExpenses'] as num?) ?? 0;
        final income =
            (data['totalPayments'] as num?) ??
            (data['totalIncome'] as num?) ??
            0;
        final net =
            (data['netProfit'] as num?) ??
            (data['net'] as num?) ??
            income - expenses;
        totalExpenses += expenses;
        totalIncome += income;
        totalNet += net;
        expensesByProjectId[doc.id] = expenses.toDouble();
        incomeByProjectId[doc.id] = income.toDouble();
        if ('${data['status'] ?? 'active'}' == 'active') {
          activeProjects += 1;
        }
      }

      final pending = _workspacePendingDelta(
        actions: latestActions,
        workspaceId: workspaceId,
        expensesByProjectId: expensesByProjectId,
        incomeByProjectId: incomeByProjectId,
      );

      controller.add(<String, num>{
        'totalProjects': projects.length + pending.pendingProjects,
        'activeProjects': activeProjects + pending.pendingProjects,
        'totalExpenses': totalExpenses + pending.pendingExpenses,
        'totalIncome': totalIncome + pending.pendingIncome,
        'net': totalNet + pending.pendingIncome - pending.pendingExpenses,
      });
    }

    final projectSub = projectsStream.listen((snapshot) {
      latestProjects = snapshot;
      emit();
    }, onError: controller.addError);
    final metricsSub = metricsStream.listen((snapshot) {
      latestMetrics = snapshot;
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await projectSub.cancel();
      await metricsSub.cancel();
      await queueSub.cancel();
    };
  });
}

Stream<Map<String, num>> _weeklySummaryStream({
  required DocSource source,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final week = utcIsoWeekBounds();
  final startDate = week.start;
  final endDate = week.end;

  final expensesStream = source.watch(
    DocQuery(
      'expenses',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final paymentsStream = source.watch(
    DocQuery(
      'payments',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final workerEntriesStream = source.watch(
    DocQuery(
      'worker_entries',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    List<Doc>? latestExpenses;
    List<Doc>? latestPayments;
    List<Doc>? latestWorkerEntries;
    List<OfflineAction> latestActions = const [];

    void emit() {
      const emptyDocs = <Doc>[];
      var weeklyExpenses = 0.0;
      var weeklyIncome = 0.0;

      for (final doc in latestExpenses ?? emptyDocs) {
        weeklyExpenses += ((doc.data['amount'] as num?) ?? 0).toDouble();
      }
      for (final doc in latestWorkerEntries ?? emptyDocs) {
        weeklyExpenses += _workerEntryCost(doc.data);
      }
      for (final doc in latestPayments ?? emptyDocs) {
        weeklyIncome += _cashInFromMap(doc.data);
      }

      final pending = _weeklyPendingDelta(
        actions: latestActions,
        workspaceId: workspaceId,
        startDate: startDate,
        endDate: endDate,
      );

      controller.add(<String, num>{
        'weeklyExpenses': weeklyExpenses + pending.pendingExpenses,
        'weeklyIncome': weeklyIncome + pending.pendingIncome,
        'weeklyNet':
            weeklyIncome +
            pending.pendingIncome -
            weeklyExpenses -
            pending.pendingExpenses,
      });
    }

    final expenseSub = expensesStream.listen((snapshot) {
      latestExpenses = snapshot;
      emit();
    }, onError: controller.addError);
    final paymentSub = paymentsStream.listen((snapshot) {
      latestPayments = snapshot;
      emit();
    }, onError: controller.addError);
    final workerEntrySub = workerEntriesStream.listen((snapshot) {
      latestWorkerEntries = snapshot;
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await expenseSub.cancel();
      await paymentSub.cancel();
      await workerEntrySub.cancel();
      await queueSub.cancel();
    };
  });
}

/// Previous UTC ISO week (the Monday–Sunday immediately before the current
/// UTC week used by [dashboardWeeklySummaryProvider]) workspace-wide totals. Additive,
/// read-only counterpart used to power the ▲/▼ week-over-week trend
/// indicators on the dashboard's Weekly Summary cards (v2 UI audit Problem 7).
final dashboardPreviousWeekSummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) {
      final source = ref.watch(docSourceProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _previousWeekSummaryStream(
        source: source,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

Stream<Map<String, num>> _previousWeekSummaryStream({
  required DocSource source,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final week = previousUtcIsoWeekBounds();
  final startDate = week.start;
  final endDate = week.end;

  final expensesStream = source.watch(
    DocQuery(
      'expenses',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final paymentsStream = source.watch(
    DocQuery(
      'payments',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final workerEntriesStream = source.watch(
    DocQuery(
      'worker_entries',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    List<Doc>? latestExpenses;
    List<Doc>? latestPayments;
    List<Doc>? latestWorkerEntries;
    List<OfflineAction> latestActions = const [];

    void emit() {
      const emptyDocs = <Doc>[];
      var previousWeekExpenses = 0.0;
      var previousWeekIncome = 0.0;

      for (final doc in latestExpenses ?? emptyDocs) {
        previousWeekExpenses += ((doc.data['amount'] as num?) ?? 0).toDouble();
      }
      for (final doc in latestWorkerEntries ?? emptyDocs) {
        previousWeekExpenses += _workerEntryCost(doc.data);
      }
      for (final doc in latestPayments ?? emptyDocs) {
        previousWeekIncome += _cashInFromMap(doc.data);
      }

      final pending = _weeklyPendingDelta(
        actions: latestActions,
        workspaceId: workspaceId,
        startDate: startDate,
        endDate: endDate,
      );

      controller.add(<String, num>{
        'previousWeekExpenses': previousWeekExpenses + pending.pendingExpenses,
        'previousWeekIncome': previousWeekIncome + pending.pendingIncome,
        'previousWeekNet':
            previousWeekIncome +
            pending.pendingIncome -
            previousWeekExpenses -
            pending.pendingExpenses,
      });
    }

    final expenseSub = expensesStream.listen((snapshot) {
      latestExpenses = snapshot;
      emit();
    }, onError: controller.addError);
    final paymentSub = paymentsStream.listen((snapshot) {
      latestPayments = snapshot;
      emit();
    }, onError: controller.addError);
    final workerEntrySub = workerEntriesStream.listen((snapshot) {
      latestWorkerEntries = snapshot;
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await expenseSub.cancel();
      await paymentSub.cancel();
      await workerEntrySub.cancel();
      await queueSub.cancel();
    };
  });
}

/// Derived "Workers this week" summary (v2 UI audit Task B2, construction-
/// specific improvements list + Problem 6: the dashboard should surface who
/// actually worked, not just financial totals). Built entirely from the
/// existing `worker_entries` ledger collection (the same manually-logged
/// "worker worked N days on date X" records used for payroll/cost by
/// add_worker_entry_screen.dart) — no new Firestore fields or Cloud
/// Functions. Uses the SAME UTC ISO week as [dashboardWeeklySummaryProvider] /
/// [dashboardPreviousWeekSummaryProvider] for consistency.
class WorkerAttendanceSummary {
  const WorkerAttendanceSummary({
    required this.workerCount,
    required this.manDays,
  });

  /// Count of distinct workers with at least one entry in the window.
  final int workerCount;

  /// Sum of `daysWorked` across all entries in the window.
  final double manDays;

  static const empty = WorkerAttendanceSummary(workerCount: 0, manDays: 0);
}

/// Workspace + UTC-ISO-week scoped query against `worker_entries` —
/// mirrors the shape of [_weeklySummaryStream] (same collection-query
/// pattern as `expenses`/`payments`, just applied to `worker_entries`, which
/// carries the same `workspaceId` + `isArchived` + `date` fields). This is a
/// bounded read (one workspace, one week), not an unbounded all-time/all-
/// workspace listener.
final dashboardWorkerAttendanceProvider =
    StreamProvider.family<WorkerAttendanceSummary, String>((ref, workspaceId) {
      final source = ref.watch(docSourceProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _workerAttendanceStream(
        source: source,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

Stream<WorkerAttendanceSummary> _workerAttendanceStream({
  required DocSource source,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final week = utcIsoWeekBounds();
  final startDate = week.start;
  final endDate = week.end;

  final entriesStream = source.watch(
    DocQuery(
      'worker_entries',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
      rangeField: 'date',
      rangeFrom: startDate,
      rangeTo: endDate,
    ),
  );
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    List<Doc>? latestEntries;
    List<OfflineAction> latestActions = const [];

    bool inWindow(DateTime date) {
      return !date.isBefore(startDate) && !date.isAfter(endDate);
    }

    void emit() {
      final docs = latestEntries ?? const [];
      // entryId -> workerId for every base (already in-window, per the
      // Firestore query above) worker_entries doc. Kept keyed by entryId
      // (rather than folded straight into a Set<String>) so a pending
      // updateWorkerEntry/archiveWorkerEntry action that moves ITS entry out
      // of the window can be excluded below without blindly dropping the
      // worker from the distinct count — the worker may still have another
      // entry (base or pending) that keeps them in-window.
      final baseWorkerIdByEntryId = <String, String>{};
      final removedEntryIds = <String>{};
      final pendingCreatedWorkerIds = <String>{};
      var manDays = 0.0;

      for (final doc in docs) {
        final data = doc.data;
        final workerId = '${data['workerId'] ?? ''}';
        if (workerId.isNotEmpty) {
          baseWorkerIdByEntryId[doc.id] = workerId;
        }
        manDays += ((data['daysWorked'] as num?) ?? 0).toDouble();
      }

      for (final action in latestActions) {
        if (!_shouldApplyPendingWeeklyAction(action)) {
          continue;
        }
        final payload = action.payload;
        if ('${payload['workspaceId'] ?? ''}' != workspaceId) {
          continue;
        }

        switch (action.type) {
          case OfflineActionTypes.createWorkerEntry:
            final date = _parsePendingDate(payload['date']) ?? action.createdAt;
            if (!inWindow(date)) {
              break;
            }
            final workerId = '${payload['workerId'] ?? ''}';
            if (workerId.isNotEmpty) {
              pendingCreatedWorkerIds.add(workerId);
            }
            manDays += ((payload['daysWorked'] as num?) ?? 0).toDouble();
            break;
          case OfflineActionTypes.updateWorkerEntry:
            // WorkspaceMutationService.updateWorkerEntry carries both the
            // new `date` and the `previousDate`, so an offline edit can move
            // an entry's date in or out of the rolling 7-day window before
            // Firestore syncs it — meaning the base query above still
            // reflects the entry's OLD date/daysWorked. Replicate the same
            // four-case dateInWindow/previousInWindow handling that
            // _weeklyPendingDelta already uses for expenses/payments instead
            // of just skipping when the NEW date happens to fall outside
            // the window.
            final date = _parsePendingDate(payload['date']) ?? action.createdAt;
            final previousDate = _parsePendingDate(payload['previousDate']);
            final daysWorked = ((payload['daysWorked'] as num?) ?? 0)
                .toDouble();
            final previousDaysWorked =
                ((payload['previousDaysWorked'] as num?) ?? 0).toDouble();
            final dateInWindow = inWindow(date);
            final previousInWindow =
                previousDate != null && inWindow(previousDate);

            if (dateInWindow && previousInWindow) {
              manDays += daysWorked - previousDaysWorked;
            } else if (dateInWindow && !previousInWindow) {
              manDays += daysWorked;
            } else if (!dateInWindow && previousInWindow) {
              manDays -= previousDaysWorked;
            }
            // else out+out: no-op, matches _weeklyPendingDelta.

            // The worker assigned to an entry never changes on update (only
            // project/days/wage/date/notes can) — the payload doesn't even
            // carry a `workerId` — so distinct-worker membership for this
            // entryId only needs revisiting when the edit moves it OUT of
            // the window. Record that here; the final set is rebuilt below
            // from whichever base entries survive.
            if (!dateInWindow) {
              final entryId = '${payload['entryId'] ?? ''}';
              if (entryId.isNotEmpty) {
                removedEntryIds.add(entryId);
              }
            }
            break;
          case OfflineActionTypes.archiveWorkerEntry:
            final date = _parsePendingDate(payload['date']) ?? action.createdAt;
            if (inWindow(date)) {
              manDays -= ((payload['daysWorked'] as num?) ?? 0).toDouble();
            }
            final entryId = '${payload['entryId'] ?? ''}';
            if (entryId.isNotEmpty) {
              removedEntryIds.add(entryId);
            }
            break;
          default:
            break;
        }
      }

      final workerIds = <String>{};
      baseWorkerIdByEntryId.forEach((entryId, workerId) {
        if (!removedEntryIds.contains(entryId)) {
          workerIds.add(workerId);
        }
      });
      workerIds.addAll(pendingCreatedWorkerIds);

      controller.add(
        WorkerAttendanceSummary(
          workerCount: workerIds.length,
          manDays: manDays < 0 ? 0 : manDays,
        ),
      );
    }

    final entriesSub = entriesStream.listen((snapshot) {
      latestEntries = snapshot;
      emit();
    }, onError: controller.addError);
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await entriesSub.cancel();
      await queueSub.cancel();
    };
  });
}

/// Cash Collected vs. Outstanding Payments (v2 UI audit Task B3,
/// Construction-Specific Improvements: the dashboard should show what's
/// actually been collected vs. what remains outstanding, not just a single
/// net financial figure). Derived entirely from the existing `payments`
/// ledger's `paymentStatus` field (`lib/core/constants/payment_statuses.dart`)
/// — no new Firestore fields or Cloud Functions.
///
/// Status semantics (confirmed by reading `add_payment_screen.dart` and
/// `PaymentRecord`, not assumed): a payment record carries a single `amount`
/// field — there is no separate "amount paid" vs. "amount still due" split
/// like `WorkerAccountingRecord.paidAmount` has for worker wages. So for a
/// client payment record, `amount` is simply the cash figure the user typed
/// in for that entry, and `paymentStatus` tags its collection state:
///   - `paid`: the full `amount` was received → counts as collected.
///   - `partial`: the user is deliberately logging a partial receipt — the
///     `amount` field IS what was actually received for this entry (there is
///     no separate larger "invoice total" tracked anywhere), it just doesn't
///     fully settle whatever is owed. That still means real cash changed
///     hands, so it counts as collected too, same as `paid`.
///   - `unpaid`: an expected/invoiced amount that has NOT been received yet
///     → counts as outstanding.
///   - `refunded` / `cancelled`: excluded from both buckets — refunded cash
///     was collected and then given back (not currently held), and a
///     cancelled record never happened.
///
/// Split (post-launch audit fix) into two independently-shaped reads instead
/// of one unbounded live listener over the entire `payments` collection:
///
///  * [dashboardCashCollectedProvider] — `paid` + `partial` sums need to scan
///    the whole workspace ledger (collection status is open-ended, so there's
///    no date bound to apply), but don't need to be *live*: a fresh figure on
///    screen load / pull-to-refresh is enough, same tradeoff already made for
///    other one-time dashboard reads. A `FutureProvider.family` doing a single
///    `.get()` (matching the convention already used by
///    `expenseDetailsProvider`/`paymentDetailsProvider`/
///    `reportScopedRowsProvider`) replaces the old `.snapshots()` listener, so
///    a mature workspace's full historical payment count is read once per
///    mount/refresh instead of being held open as a live subscription for as
///    long as the dashboard — the app's highest-traffic, longest-dwell
///    screen — stays mounted.
///  * [dashboardOutstandingPaymentsProvider] — genuinely wants to stay live
///    (a collections-risk signal), but the query is now filtered
///    server-side to `paymentStatus == unpaid`, so the listener's document
///    count is bounded by the currently-outstanding subset rather than the
///    workspace's entire payment history. `paid`/`partial`/`refunded`/
///    `cancelled` docs (which only grow over time) never enter this
///    listener at all; the set shrinks as outstanding payments get marked
///    paid.
///
/// No double-counting: a payment's `paymentStatus` puts it in exactly one of
/// three buckets — collected (`paid`/`partial`/missing-field legacy docs,
/// which default to `paid` the same way `Payment.fromMap` does), outstanding
/// (`unpaid`), or neither (`refunded`/`cancelled`, unchanged from before this
/// split) — never both, and never silently dropped from a bucket it should
/// be in.
final dashboardCashCollectedProvider = FutureProvider.family<double, String>((
  ref,
  workspaceId,
) async {
  final source = ref.watch(docSourceProvider);
  return _fetchCashCollected(source: source, workspaceId: workspaceId);
});

Future<double> _fetchCashCollected({
  required DocSource source,
  required String workspaceId,
}) async {
  final snapshot = await source.get(
    DocQuery(
      'payments',
      equals: {'workspaceId': workspaceId, 'isArchived': false},
    ),
  );

  var collected = 0.0;
  for (final doc in snapshot) {
    final data = doc.data;
    collected += cashCollectedAmount(
      amount: ((data['amount'] as num?) ?? 0).toDouble(),
      paymentStatus: data['paymentStatus'] as String?,
      paidAmount: (data['paidAmount'] as num?)?.toDouble(),
    );
  }
  return collected;
}

/// Workspace-scoped listener over the `payments` collection, bounded
/// server-side to `paymentStatus == unpaid` — see the doc comment above
/// [dashboardCashCollectedProvider] for the full cost rationale.
final dashboardOutstandingPaymentsProvider =
    StreamProvider.family<double, String>((ref, workspaceId) {
      final source = ref.watch(docSourceProvider);
      return _outstandingPaymentsStream(
        source: source,
        workspaceId: workspaceId,
      );
    });

Stream<double> _outstandingPaymentsStream({
  required DocSource source,
  required String workspaceId,
}) {
  // Outstanding is approximated from the first 500 unpaid payment docs.
  return source
      .watch(
        DocQuery(
          'payments',
          equals: {
            'workspaceId': workspaceId,
            'isArchived': false,
            'paymentStatus': PaymentStatuses.unpaid,
          },
          limit: 500,
        ),
      )
      .map((snapshot) {
        var outstanding = 0.0;
        for (final doc in snapshot) {
          outstanding += ((doc.data['amount'] as num?) ?? 0).toDouble();
        }
        return outstanding;
      });
}

({num pendingExpenses, num pendingIncome}) _weeklyPendingDelta({
  required List<OfflineAction> actions,
  required String workspaceId,
  required DateTime startDate,
  required DateTime endDate,
}) {
  var pendingExpenses = 0.0;
  var pendingIncome = 0.0;

  bool inWindow(DateTime date) {
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }

  for (final action in actions) {
    if (!_shouldApplyPendingWeeklyAction(action)) {
      continue;
    }
    final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
    if (payloadWorkspaceId != workspaceId) {
      continue;
    }

    final date = _parsePendingDate(action.payload['date']) ?? action.createdAt;
    final previousDate = _parsePendingDate(action.payload['previousDate']);
    final amount = ((action.payload['amount'] as num?) ?? 0).toDouble();
    final previousAmount = ((action.payload['previousAmount'] as num?) ?? 0)
        .toDouble();

    final dateInWindow = inWindow(date);
    final previousInWindow = previousDate != null && inWindow(previousDate);

    switch (action.type) {
      case OfflineActionTypes.createExpense:
        if (dateInWindow) {
          pendingExpenses += amount;
        }
        break;
      case OfflineActionTypes.updateExpense:
        if (dateInWindow && previousInWindow) {
          pendingExpenses += amount - previousAmount;
        } else if (dateInWindow && !previousInWindow) {
          pendingExpenses += amount;
        } else if (!dateInWindow && previousInWindow) {
          pendingExpenses -= previousAmount;
        }
        break;
      case OfflineActionTypes.archiveExpense:
        if (dateInWindow) {
          pendingExpenses -= amount;
        }
        break;
      case OfflineActionTypes.createPayment:
        if (dateInWindow) {
          pendingIncome += _cashInFromMap(action.payload);
        }
        break;
      case OfflineActionTypes.updatePayment:
        final nextCash = _cashInFromMap(action.payload);
        final previousCash = cashCollectedAmount(
          amount: previousAmount,
          paymentStatus:
              (action.payload['previousPaymentStatus'] as String?) ??
              (action.payload['paymentStatus'] as String?),
          paidAmount: (action.payload['previousPaidAmount'] as num?)
              ?.toDouble(),
        );
        if (dateInWindow && previousInWindow) {
          pendingIncome += nextCash - previousCash;
        } else if (dateInWindow && !previousInWindow) {
          pendingIncome += nextCash;
        } else if (!dateInWindow && previousInWindow) {
          pendingIncome -= previousCash;
        }
        break;
      case OfflineActionTypes.archivePayment:
        if (dateInWindow) {
          pendingIncome -= _cashInFromMap(action.payload);
        }
        break;
      case OfflineActionTypes.createWorkerEntry:
        if (dateInWindow) {
          pendingExpenses += _workerEntryCost(action.payload);
        }
        break;
      case OfflineActionTypes.updateWorkerEntry:
        final nextCost = _workerEntryCost(action.payload);
        final previousCost = _workerEntryCost({
          'totalCost': action.payload['previousTotalCost'],
          'daysWorked': action.payload['previousDaysWorked'],
          'dailyWage': action.payload['previousDailyWage'],
        });
        if (dateInWindow && previousInWindow) {
          pendingExpenses += nextCost - previousCost;
        } else if (dateInWindow && !previousInWindow) {
          pendingExpenses += nextCost;
        } else if (!dateInWindow && previousInWindow) {
          pendingExpenses -= previousCost;
        }
        break;
      case OfflineActionTypes.archiveWorkerEntry:
        if (dateInWindow) {
          pendingExpenses -= _workerEntryCost(action.payload);
        }
        break;
      default:
        break;
    }
  }

  return (pendingExpenses: pendingExpenses, pendingIncome: pendingIncome);
}

bool _shouldApplyPendingWeeklyAction(OfflineAction action) {
  return action.status != OfflineActionStatus.synced &&
      action.status != OfflineActionStatus.deadLetter;
}

DateTime? _parsePendingDate(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

({int pendingProjects, num pendingExpenses, num pendingIncome})
_workspacePendingDelta({
  required List<OfflineAction> actions,
  required String workspaceId,
  required Map<String, double> expensesByProjectId,
  required Map<String, double> incomeByProjectId,
}) {
  var pendingProjects = 0;
  num pendingExpenses = 0;
  num pendingIncome = 0;

  for (final action in actions) {
    final payloadWorkspaceId = '${action.payload['workspaceId'] ?? ''}';
    if (payloadWorkspaceId != workspaceId) {
      continue;
    }
    switch (action.type) {
      case OfflineActionTypes.createProject:
        if (action.status == OfflineActionStatus.synced) {
          break;
        }
        pendingProjects += 1;
        break;
      case OfflineActionTypes.createExpense:
        pendingExpenses += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalExpensesBefore',
          currentTotal:
              expensesByProjectId['${action.payload['projectId'] ?? ''}'],
          delta: ((action.payload['amount'] as num?) ?? 0).toDouble(),
        );
        break;
      case OfflineActionTypes.updateExpense:
        pendingExpenses += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalExpensesBefore',
          currentTotal:
              expensesByProjectId['${action.payload['projectId'] ?? ''}'],
          delta:
              (((action.payload['amount'] as num?) ?? 0) -
                      ((action.payload['previousAmount'] as num?) ?? 0))
                  .toDouble(),
        );
        break;
      case OfflineActionTypes.createWorkerEntry:
        final daysWorked = (action.payload['daysWorked'] as num?) ?? 0;
        final dailyWage = (action.payload['dailyWage'] as num?) ?? 0;
        pendingExpenses += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalExpensesBefore',
          currentTotal:
              expensesByProjectId['${action.payload['projectId'] ?? ''}'],
          delta: (daysWorked * dailyWage).toDouble(),
        );
        break;
      case OfflineActionTypes.updateWorkerEntry:
        final previousCost =
            (action.payload['previousTotalCost'] as num?) ??
            (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                ((action.payload['previousDailyWage'] as num?) ?? 0));
        final nextCost =
            (action.payload['totalCost'] as num?) ??
            (((action.payload['daysWorked'] as num?) ?? 0) *
                ((action.payload['dailyWage'] as num?) ?? 0));
        final delta = nextCost - previousCost;
        pendingExpenses += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalExpensesBefore',
          currentTotal:
              expensesByProjectId['${action.payload['projectId'] ?? ''}'],
          delta: delta.toDouble(),
        );
        break;
      case OfflineActionTypes.createPayment:
        pendingIncome += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalPaymentsBefore',
          currentTotal:
              incomeByProjectId['${action.payload['projectId'] ?? ''}'],
          delta: _cashInFromMap(action.payload),
        );
        break;
      case OfflineActionTypes.updatePayment:
        pendingIncome += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalPaymentsBefore',
          currentTotal:
              incomeByProjectId['${action.payload['projectId'] ?? ''}'],
          delta:
              _cashInFromMap(action.payload) -
              cashCollectedAmount(
                amount: ((action.payload['previousAmount'] as num?) ?? 0)
                    .toDouble(),
                paymentStatus:
                    (action.payload['previousPaymentStatus'] as String?) ??
                    (action.payload['paymentStatus'] as String?),
                paidAmount: (action.payload['previousPaidAmount'] as num?)
                    ?.toDouble(),
              ),
        );
        break;
      default:
        break;
    }
  }

  return (
    pendingProjects: pendingProjects,
    pendingExpenses: pendingExpenses,
    pendingIncome: pendingIncome,
  );
}

double _dashboardDeltaIfNeeded({
  required OfflineAction action,
  required String baselineField,
  required double? currentTotal,
  required double delta,
}) {
  final baseline = (action.payload[baselineField] as num?)?.toDouble();
  if (baseline == null || currentTotal == null || delta == 0) {
    return delta;
  }
  final expected =
      (action.payload[baselineField.replaceFirst('Before', 'After')] as num?)
          ?.toDouble() ??
      baseline + delta;
  final reflected = delta > 0
      ? currentTotal >= expected
      : currentTotal <= expected;
  return reflected ? 0 : delta;
}

double _workerEntryCost(Map<String, dynamic> data) {
  final totalCost = (data['totalCost'] as num?)?.toDouble();
  if (totalCost != null) {
    return totalCost;
  }
  return ((data['daysWorked'] as num?) ?? 0).toDouble() *
      ((data['dailyWage'] as num?) ?? 0).toDouble();
}

double _cashInFromMap(Map<String, dynamic> data) {
  return cashCollectedAmount(
    amount: ((data['amount'] as num?) ?? 0).toDouble(),
    paymentStatus: data['paymentStatus'] as String?,
    paidAmount: (data['paidAmount'] as num?)?.toDouble(),
  );
}
