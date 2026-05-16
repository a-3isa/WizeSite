import 'package:buildtrack_app/core/providers/firebase_providers.dart';
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

final reportMetricsProvider = StreamProvider<ReportMetrics?>((ref) {
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
