import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reportProjectIdProvider = StateProvider<String?>((ref) => null);

class MonthlyFlowData {
  const MonthlyFlowData({
    required this.month,
    required this.expenses,
    required this.income,
  });

  final DateTime month;
  final double expenses;
  final double income;
}

class WorkerCostData {
  const WorkerCostData({
    required this.name,
    required this.totalCost,
    required this.totalDays,
  });

  final String name;
  final double totalCost;
  final double totalDays;
}

class ReportMetrics {
  const ReportMetrics({
    required this.projectId,
    required this.projectName,
    required this.status,
    required this.isArchived,
    required this.totalExpenses,
    required this.totalIncome,
    required this.net,
    required this.categoryTotals,
    required this.monthlyFlow,
    required this.topWorkers,
    required this.recentExpenses,
    required this.recentPayments,
  });

  final String projectId;
  final String projectName;
  final String status;
  final bool isArchived;
  final double totalExpenses;
  final double totalIncome;
  final double net;
  final Map<String, double> categoryTotals;
  final List<MonthlyFlowData> monthlyFlow;
  final List<WorkerCostData> topWorkers;
  final List<Expense> recentExpenses;
  final List<PaymentRecord> recentPayments;

  factory ReportMetrics.fromMap(String id, Map<String, dynamic> map) {
    final totalExpenses = (map['totalExpenses'] as num?)?.toDouble() ?? 0;
    final totalIncome =
        (map['totalIncome'] as num?)?.toDouble() ??
        (map['totalPayments'] as num?)?.toDouble() ??
        0;
    final net =
        (map['net'] as num?)?.toDouble() ??
        (map['netProfit'] as num?)?.toDouble() ??
        totalIncome - totalExpenses;

    final categoryMap = <String, double>{};
    final rawCategoryTotals = map['categoryTotals'];
    if (rawCategoryTotals is Map) {
      for (final entry in rawCategoryTotals.entries) {
        categoryMap['${entry.key}'] = (entry.value as num?)?.toDouble() ?? 0;
      }
    }

    final flow = <MonthlyFlowData>[];
    final rawFlow = map['monthlyFlow'];
    if (rawFlow is List) {
      for (final item in rawFlow) {
        if (item is! Map) {
          continue;
        }
        final monthKey = '${item['month'] ?? ''}'.trim();
        final month = monthKey.isEmpty
            ? DateTime.now()
            : DateTime.tryParse('$monthKey-01') ?? DateTime.now();
        flow.add(
          MonthlyFlowData(
            month: month,
            expenses: (item['expenses'] as num?)?.toDouble() ?? 0,
            income: (item['income'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }

    final workers = <WorkerCostData>[];
    final rawWorkers = map['topWorkers'];
    if (rawWorkers is List) {
      for (final item in rawWorkers) {
        if (item is! Map) {
          continue;
        }
        workers.add(
          WorkerCostData(
            name: '${item['name'] ?? item['workerId'] ?? ''}'.trim(),
            totalCost: (item['totalCost'] as num?)?.toDouble() ?? 0,
            totalDays: (item['totalDays'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }

    List<Expense> expenses = const [];
    final rawExpenses = map['recentExpenses'];
    if (rawExpenses is List) {
      expenses = rawExpenses
          .whereType<Map>()
          .map((item) => Expense.fromMap('${item['id'] ?? ''}', item.cast()))
          .toList();
    }

    List<PaymentRecord> payments = const [];
    final rawPayments = map['recentPayments'];
    if (rawPayments is List) {
      payments = rawPayments
          .whereType<Map>()
          .map(
            (item) => PaymentRecord.fromMap('${item['id'] ?? ''}', item.cast()),
          )
          .toList();
    }

    return ReportMetrics(
      projectId: '${map['projectId'] ?? id}',
      projectName: '${map['projectName'] ?? ''}',
      status: '${map['status'] ?? 'active'}',
      isArchived: map['isArchived'] as bool? ?? false,
      totalExpenses: totalExpenses,
      totalIncome: totalIncome,
      net: net,
      categoryTotals: categoryMap,
      monthlyFlow: flow,
      topWorkers: workers,
      recentExpenses: expenses,
      recentPayments: payments,
    );
  }
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

String _monthKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

List<MonthlyFlowData> _mergeMonthlyFlow(
  List<MonthlyFlowData> base,
  List<OfflineAction> actions,
  String projectId,
) {
  final points = <String, MonthlyFlowData>{
    for (final item in base) _monthKey(item.month): item,
  };

  MonthlyFlowData pointFor(DateTime date) {
    final key = _monthKey(DateTime.utc(date.year, date.month));
    return points.putIfAbsent(
      key,
      () => MonthlyFlowData(
        month: DateTime.utc(date.year, date.month),
        expenses: 0,
        income: 0,
      ),
    );
  }

  for (final action in actions) {
    if ('${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    final date = _parsePendingDate(action.payload['date']);
    if (date == null) {
      continue;
    }
    final point = pointFor(date);
    switch (action.type) {
      case OfflineActionTypes.createExpense:
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses + ((action.payload['amount'] as num?) ?? 0),
          income: point.income,
        );
        break;
      case OfflineActionTypes.archiveExpense:
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses - ((action.payload['amount'] as num?) ?? 0),
          income: point.income,
        );
        break;
      case OfflineActionTypes.updateExpense:
        final previousDate = _parsePendingDate(action.payload['previousDate']);
        final previousAmount =
            ((action.payload['previousAmount'] as num?) ?? 0).toDouble();
        if (previousDate != null) {
          final previousPoint = pointFor(previousDate);
          points[_monthKey(previousPoint.month)] = MonthlyFlowData(
            month: previousPoint.month,
            expenses: previousPoint.expenses - previousAmount,
            income: previousPoint.income,
          );
        }
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses:
              point.expenses + ((action.payload['amount'] as num?) ?? 0),
          income: point.income,
        );
        break;
      case OfflineActionTypes.createWorkerEntry:
        final cost =
            ((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                    ((action.payload['dailyWage'] as num?) ?? 0)))
                .toDouble();
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses + cost,
          income: point.income,
        );
        break;
      case OfflineActionTypes.archiveWorkerEntry:
        final cost =
            ((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                    ((action.payload['dailyWage'] as num?) ?? 0)))
                .toDouble();
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses - cost,
          income: point.income,
        );
        break;
      case OfflineActionTypes.createPayment:
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses,
          income: point.income + ((action.payload['amount'] as num?) ?? 0),
        );
        break;
      case OfflineActionTypes.archivePayment:
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses,
          income: point.income - ((action.payload['amount'] as num?) ?? 0),
        );
        break;
      case OfflineActionTypes.updatePayment:
        final previousDate = _parsePendingDate(action.payload['previousDate']);
        final previousAmount =
            ((action.payload['previousAmount'] as num?) ?? 0).toDouble();
        if (previousDate != null) {
          final previousPoint = pointFor(previousDate);
          points[_monthKey(previousPoint.month)] = MonthlyFlowData(
            month: previousPoint.month,
            expenses: previousPoint.expenses,
            income: previousPoint.income - previousAmount,
          );
        }
        points[_monthKey(point.month)] = MonthlyFlowData(
          month: point.month,
          expenses: point.expenses,
          income: point.income + ((action.payload['amount'] as num?) ?? 0),
        );
        break;
      default:
        break;
    }
  }

  final merged = points.values.toList()
    ..sort((a, b) => a.month.compareTo(b.month));
  return merged;
}

Map<String, double> _mergeCategoryTotals(
  Map<String, double> base,
  List<OfflineAction> actions,
  String projectId,
) {
  final totals = Map<String, double>.from(base);

  void addToCategory(String category, double delta) {
    final nextValue = (totals[category] ?? 0) + delta;
    if (nextValue == 0) {
      totals.remove(category);
      return;
    }
    totals[category] = nextValue;
  }

  for (final action in actions) {
    if ('${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    switch (action.type) {
      case OfflineActionTypes.createExpense:
        addToCategory(
          '${action.payload['category'] ?? 'other'}',
          ((action.payload['amount'] as num?) ?? 0).toDouble(),
        );
        break;
      case OfflineActionTypes.archiveExpense:
        addToCategory(
          '${action.payload['category'] ?? 'other'}',
          -((action.payload['amount'] as num?) ?? 0).toDouble(),
        );
        break;
      case OfflineActionTypes.updateExpense:
        addToCategory(
          '${action.payload['previousCategory'] ?? 'other'}',
          -((action.payload['previousAmount'] as num?) ?? 0).toDouble(),
        );
        addToCategory(
          '${action.payload['category'] ?? 'other'}',
          ((action.payload['amount'] as num?) ?? 0).toDouble(),
        );
        break;
      case OfflineActionTypes.createWorkerEntry:
        addToCategory(
          'labor',
          ((action.payload['totalCost'] as num?)?.toDouble() ??
              (((action.payload['daysWorked'] as num?) ?? 0) *
                      ((action.payload['dailyWage'] as num?) ?? 0))
                  .toDouble()),
        );
        break;
      case OfflineActionTypes.archiveWorkerEntry:
        addToCategory(
          'labor',
          -((action.payload['totalCost'] as num?)?.toDouble() ??
              (((action.payload['daysWorked'] as num?) ?? 0) *
                      ((action.payload['dailyWage'] as num?) ?? 0))
                  .toDouble()),
        );
        break;
      default:
        break;
    }
  }

  return totals;
}

List<Expense> _mergeRecentExpenses(
  List<Expense> base,
  List<OfflineAction> actions,
  String projectId,
) {
  final items = List<Expense>.from(base);
  final archivedIds = <String>{};

  for (final action in actions) {
    if ('${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    if (action.type == OfflineActionTypes.archiveExpense) {
      final expenseId = '${action.payload['expenseId'] ?? ''}';
      if (expenseId.isNotEmpty) {
        archivedIds.add(expenseId);
      }
    }
  }

  if (archivedIds.isNotEmpty) {
    items.removeWhere((item) => archivedIds.contains(item.id));
  }

  final liveMutationIds = items
      .map((item) => item.clientMutationId)
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final action in actions) {
    if (action.type != OfflineActionTypes.createExpense ||
        '${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
    if (clientMutationId.isNotEmpty &&
        liveMutationIds.contains(clientMutationId)) {
      continue;
    }
    items.insert(
      0,
      Expense(
        id: 'pending_${action.id}',
        workspaceId: '${action.payload['workspaceId'] ?? ''}',
        projectId: '${action.payload['projectId'] ?? ''}',
        projectName: '${action.payload['projectName'] ?? ''}',
        category: '${action.payload['category'] ?? 'other'}',
        amount: ((action.payload['amount'] as num?) ?? 0).toDouble(),
        currency: '${action.payload['currency'] ?? 'EGP'}',
        date: _parsePendingDate(action.payload['date']) ?? action.createdAt,
        notes: '${action.payload['notes'] ?? ''}',
        supplierName: '${action.payload['supplierName'] ?? ''}',
        paymentMethod: '${action.payload['paymentMethod'] ?? ''}',
        inputMethod: 'manual',
        transcript: '${action.payload['transcript'] ?? ''}',
        source: 'pending',
        storagePath: '${action.payload['storagePath'] ?? ''}',
        isArchived: false,
        clientMutationId: '${action.payload['clientMutationId'] ?? action.id}',
      ),
    );
  }

  final deduped = <String, Expense>{};
  for (final item in items) {
    deduped[item.id] = item;
  }
  final merged = deduped.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return merged.take(5).toList(growable: false);
}

List<PaymentRecord> _mergeRecentPayments(
  List<PaymentRecord> base,
  List<OfflineAction> actions,
  String projectId,
) {
  final items = List<PaymentRecord>.from(base);
  final archivedIds = <String>{};

  for (final action in actions) {
    if ('${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    if (action.type == OfflineActionTypes.archivePayment) {
      final paymentId = '${action.payload['paymentId'] ?? ''}';
      if (paymentId.isNotEmpty) {
        archivedIds.add(paymentId);
      }
    }
  }

  if (archivedIds.isNotEmpty) {
    items.removeWhere((item) => archivedIds.contains(item.id));
  }

  final liveMutationIds = items
      .map((item) => item.clientMutationId)
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final action in actions) {
    if (action.type != OfflineActionTypes.createPayment ||
        '${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    final clientMutationId = '${action.payload['clientMutationId'] ?? ''}';
    if (clientMutationId.isNotEmpty &&
        liveMutationIds.contains(clientMutationId)) {
      continue;
    }
    items.insert(
      0,
      PaymentRecord(
        id: 'pending_${action.id}',
        workspaceId: '${action.payload['workspaceId'] ?? ''}',
        projectId: '${action.payload['projectId'] ?? ''}',
        amount: ((action.payload['amount'] as num?) ?? 0).toDouble(),
        date: _parsePendingDate(action.payload['date']) ?? action.createdAt,
        paymentMethod: '${action.payload['paymentMethod'] ?? 'cash'}',
        notes: '${action.payload['notes'] ?? ''}',
        isArchived: false,
        clientMutationId: '${action.payload['clientMutationId'] ?? action.id}',
      ),
    );
  }

  final deduped = <String, PaymentRecord>{};
  for (final item in items) {
    deduped[item.id] = item;
  }
  final merged = deduped.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return merged.take(5).toList(growable: false);
}

ReportMetrics? _mergePendingActionsIntoMetrics(
  ReportMetrics? base,
  List<OfflineAction> actions,
  String projectId,
) {
  final relevantActions = actions
      .where((action) => '${action.payload['projectId'] ?? ''}' == projectId)
      .toList(growable: false);
  if (base == null) {
    if (relevantActions.isEmpty) {
      return null;
    }

    final projectName = relevantActions
        .map((action) => '${action.payload['projectName'] ?? ''}'.trim())
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => 'Pending project',
        );
    base = ReportMetrics(
      projectId: projectId,
      projectName: projectName,
      status: 'active',
      isArchived: false,
      totalExpenses: 0,
      totalIncome: 0,
      net: 0,
      categoryTotals: const <String, double>{},
      monthlyFlow: const <MonthlyFlowData>[],
      topWorkers: const <WorkerCostData>[],
      recentExpenses: const <Expense>[],
      recentPayments: const <PaymentRecord>[],
    );
  }

  var totalExpenses = base.totalExpenses;
  var totalIncome = base.totalIncome;
  for (final action in relevantActions) {
    switch (action.type) {
      case OfflineActionTypes.createExpense:
        totalExpenses += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.archiveExpense:
        totalExpenses -= ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.updateExpense:
        totalExpenses -=
            ((action.payload['previousAmount'] as num?) ?? 0).toDouble();
        totalExpenses += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.createWorkerEntry:
        totalExpenses +=
            ((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                        ((action.payload['dailyWage'] as num?) ?? 0))
                    .toDouble());
        break;
      case OfflineActionTypes.archiveWorkerEntry:
        totalExpenses -=
            ((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                        ((action.payload['dailyWage'] as num?) ?? 0))
                    .toDouble());
        break;
      case OfflineActionTypes.createPayment:
        totalIncome += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.archivePayment:
        totalIncome -= ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.updatePayment:
        totalIncome -=
            ((action.payload['previousAmount'] as num?) ?? 0).toDouble();
        totalIncome += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      default:
        break;
    }
  }

  return ReportMetrics(
    projectId: base.projectId,
    projectName: base.projectName,
    status: base.status,
    isArchived: base.isArchived,
    totalExpenses: totalExpenses,
    totalIncome: totalIncome,
    net: totalIncome - totalExpenses,
    categoryTotals:
        _mergeCategoryTotals(base.categoryTotals, relevantActions, projectId),
    monthlyFlow: _mergeMonthlyFlow(base.monthlyFlow, relevantActions, projectId),
    topWorkers: base.topWorkers,
    recentExpenses:
        _mergeRecentExpenses(base.recentExpenses, relevantActions, projectId),
    recentPayments:
        _mergeRecentPayments(base.recentPayments, relevantActions, projectId),
  );
}

final reportBaseMetricsProvider = StreamProvider<ReportMetrics?>((ref) {
  final projectId = ref.watch(reportProjectIdProvider);
  if (projectId == null || projectId.isEmpty) {
    return Stream.value(null);
  }

  return ref
      .watch(firestoreProvider)
      .collection('project_metrics')
      .doc(projectId)
      .snapshots()
      .map((snap) {
        if (!snap.exists) {
          return null;
        }
        return ReportMetrics.fromMap(snap.id, snap.data() ?? const {});
      });
});

final reportPendingActionsProvider = StreamProvider<List<OfflineAction>>((ref) {
  return ref.watch(offlineActionQueueProvider).watch();
});

final reportMetricsProvider = Provider<AsyncValue<ReportMetrics?>>((ref) {
  final projectId = ref.watch(reportProjectIdProvider);
  if (projectId == null || projectId.isEmpty) {
    return const AsyncData(null);
  }

  final baseAsync = ref.watch(reportBaseMetricsProvider);
  final pendingAsync = ref.watch(reportPendingActionsProvider);

  return baseAsync.when(
    data: (base) => pendingAsync.when(
      data: (actions) => AsyncData(
        _mergePendingActionsIntoMetrics(base, actions, projectId),
      ),
      error: (error, stackTrace) => AsyncError(error, stackTrace),
      loading: () => const AsyncLoading(),
    ),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
    loading: () => const AsyncLoading(),
  );
});

final reportExpensesProvider = Provider<AsyncValue<List<Expense>>>((ref) {
  return ref
      .watch(reportMetricsProvider)
      .whenData((metrics) => metrics?.recentExpenses ?? const []);
});

final reportPaymentsProvider = Provider<AsyncValue<List<PaymentRecord>>>((ref) {
  return ref
      .watch(reportMetricsProvider)
      .whenData((metrics) => metrics?.recentPayments ?? const []);
});

final expensesByCategoryProvider = Provider<AsyncValue<Map<String, double>>>((
  ref,
) {
  return ref
      .watch(reportMetricsProvider)
      .whenData(
        (metrics) => metrics?.categoryTotals ?? const <String, double>{},
      );
});

final monthlyFlowProvider = Provider<AsyncValue<List<MonthlyFlowData>>>((ref) {
  return ref
      .watch(reportMetricsProvider)
      .whenData((metrics) => metrics?.monthlyFlow ?? const <MonthlyFlowData>[]);
});

final topWorkersProvider = Provider<AsyncValue<List<WorkerCostData>>>((ref) {
  return ref
      .watch(reportMetricsProvider)
      .whenData((metrics) => metrics?.topWorkers ?? const <WorkerCostData>[]);
});

final reportSummaryProvider = Provider<AsyncValue<Map<String, num>>>((ref) {
  return ref.watch(reportMetricsProvider).whenData((metrics) {
    if (metrics == null) {
      return const <String, num>{};
    }
    return <String, num>{
      'totalExpenses': metrics.totalExpenses,
      'totalIncome': metrics.totalIncome,
      'net': metrics.net,
      'totalProjects': 1,
      'activeProjects': metrics.status == 'active' && !metrics.isArchived
          ? 1
          : 0,
    };
  });
});
