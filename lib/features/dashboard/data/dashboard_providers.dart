import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/data/project_metrics_merger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardSummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) {
      final firestore = ref.watch(firestoreProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _projectsSummaryStream(
        firestore: firestore,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

final dashboardWeeklySummaryProvider =
    StreamProvider.family<Map<String, num>, String>((ref, workspaceId) {
      final firestore = ref.watch(firestoreProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _weeklySummaryStream(
        firestore: firestore,
        queue: queue,
        workspaceId: workspaceId,
      );
    });

final dashboardWeeklyInsightsProvider =
    StreamProvider.family<DashboardWeeklyInsights, String>((ref, workspaceId) {
      final firestore = ref.watch(firestoreProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      return _weeklyInsightsStream(
        firestore: firestore,
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
  required FirebaseFirestore firestore,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final now = DateTime.now();
  final startDate = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 6));
  final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final expensesStream = firestore
      .collection('expenses')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .where('date', isGreaterThanOrEqualTo: startDate)
      .where('date', isLessThanOrEqualTo: endDate)
      .snapshots();
  final paymentsStream = firestore
      .collection('payments')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .where('date', isGreaterThanOrEqualTo: startDate)
      .where('date', isLessThanOrEqualTo: endDate)
      .snapshots();
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    QuerySnapshot<Map<String, dynamic>>? latestExpenses;
    QuerySnapshot<Map<String, dynamic>>? latestPayments;
    List<OfflineAction> latestActions = const [];

    void emit() {
      final expenses = latestExpenses?.docs ?? const [];
      final payments = latestPayments?.docs ?? const [];

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
        final data = doc.data();
        final amount = ((data['amount'] as num?) ?? 0).toDouble();
        final category = '${data['category'] ?? ''}'.trim();
        final entityName = _normalizedEntityName(
          data['entityName'] ?? data['supplierName'],
        );
        final paymentMethod = '${data['paymentMethod'] ?? 'Unknown'}'.trim();
        final date = parseDate(data['date']);

        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
        if (category == 'labor') {
          laborTotal += amount;
        }
        if (category == 'equipment') {
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
        final data = doc.data();
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
        final category = '${payload['category'] ?? ''}'.trim();
        final entityName = _normalizedEntityName(
          payload['entityName'] ?? payload['supplierName'],
        );
        final paymentMethod = '${payload['paymentMethod'] ?? 'Unknown'}'.trim();

        if (action.type == OfflineActionTypes.createExpense) {
          categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
          entityTotals[entityName] = (entityTotals[entityName] ?? 0) + amount;
          if (category == 'labor') {
            laborTotal += amount;
          }
          if (category == 'equipment') {
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
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await expenseSub.cancel();
      await paymentSub.cancel();
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
  required FirebaseFirestore firestore,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final projectsStream = firestore
      .collection('projects')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .snapshots();
  final metricsStream = firestore
      .collection('project_metrics')
      .where('workspaceId', isEqualTo: workspaceId)
      .snapshots();

  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    QuerySnapshot<Map<String, dynamic>>? latestProjects;
    QuerySnapshot<Map<String, dynamic>>? latestMetrics;
    List<OfflineAction> latestActions = const [];

    void emit() {
      final projects = latestProjects?.docs ?? const [];
      final metricsByProjectId = {
        for (final doc in latestMetrics?.docs ?? const []) doc.id: doc.data(),
      };
      num totalExpenses = 0;
      num totalIncome = 0;
      num totalNet = 0;
      var activeProjects = 0;
      final expensesByProjectId = <String, double>{};
      final incomeByProjectId = <String, double>{};

      for (final doc in projects) {
        final data = mergeProjectMetricsData(
          projectData: doc.data(),
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
  required FirebaseFirestore firestore,
  required OfflineActionQueue queue,
  required String workspaceId,
}) {
  final now = DateTime.now();
  final startDate = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 6));
  final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final expensesStream = firestore
      .collection('expenses')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .where('date', isGreaterThanOrEqualTo: startDate)
      .where('date', isLessThanOrEqualTo: endDate)
      .snapshots();
  final paymentsStream = firestore
      .collection('payments')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .where('date', isGreaterThanOrEqualTo: startDate)
      .where('date', isLessThanOrEqualTo: endDate)
      .snapshots();
  final queueStream = queue.watch(includeExpiredSynced: true);

  return Stream.multi((controller) {
    QuerySnapshot<Map<String, dynamic>>? latestExpenses;
    QuerySnapshot<Map<String, dynamic>>? latestPayments;
    List<OfflineAction> latestActions = const [];

    void emit() {
      var weeklyExpenses = 0.0;
      var weeklyIncome = 0.0;

      for (final doc in latestExpenses?.docs ?? const []) {
        weeklyExpenses += ((doc.data()['amount'] as num?) ?? 0).toDouble();
      }
      for (final doc in latestPayments?.docs ?? const []) {
        weeklyIncome += ((doc.data()['amount'] as num?) ?? 0).toDouble();
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
    final queueSub = queueStream.listen((actions) {
      latestActions = actions;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await expenseSub.cancel();
      await paymentSub.cancel();
      await queueSub.cancel();
    };
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
          pendingIncome += amount;
        }
        break;
      case OfflineActionTypes.updatePayment:
        if (dateInWindow && previousInWindow) {
          pendingIncome += amount - previousAmount;
        } else if (dateInWindow && !previousInWindow) {
          pendingIncome += amount;
        } else if (!dateInWindow && previousInWindow) {
          pendingIncome -= previousAmount;
        }
        break;
      case OfflineActionTypes.archivePayment:
        if (dateInWindow) {
          pendingIncome -= amount;
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
          delta: ((action.payload['amount'] as num?) ?? 0).toDouble(),
        );
        break;
      case OfflineActionTypes.updatePayment:
        pendingIncome += _dashboardDeltaIfNeeded(
          action: action,
          baselineField: 'projectTotalPaymentsBefore',
          currentTotal:
              incomeByProjectId['${action.payload['projectId'] ?? ''}'],
          delta:
              (((action.payload['amount'] as num?) ?? 0) -
                      ((action.payload['previousAmount'] as num?) ?? 0))
                  .toDouble(),
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
