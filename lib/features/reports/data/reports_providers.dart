import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Filter ──────────────────────────────────────────────────────────

final reportProjectIdProvider = StateProvider<String?>((ref) => null);

// ─── Raw data streams ───────────────────────────────────────────────

final reportExpensesProvider = StreamProvider<List<Expense>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final projectId = ref.watch(reportProjectIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  final firestore = ref.watch(firestoreProvider);
  var query = firestore
      .collection('expenses')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false);

  if (projectId != null && projectId.isNotEmpty) {
    query = query.where('projectId', isEqualTo: projectId);
  }

  return query
      .orderBy('date', descending: true)
      .limit(500)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => Expense.fromMap(doc.id, doc.data()))
            .toList(),
      );
});

final reportPaymentsProvider = StreamProvider<List<PaymentRecord>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final projectId = ref.watch(reportProjectIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  final firestore = ref.watch(firestoreProvider);
  var query = firestore
      .collection('payments')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false);

  if (projectId != null && projectId.isNotEmpty) {
    query = query.where('projectId', isEqualTo: projectId);
  }

  return query
      .orderBy('date', descending: true)
      .limit(500)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => PaymentRecord.fromMap(doc.id, doc.data()))
            .toList(),
      );
});

final reportWorkerEntriesProvider =
    StreamProvider<List<WorkerEntryRecord>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final projectId = ref.watch(reportProjectIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  final firestore = ref.watch(firestoreProvider);
  var query = firestore
      .collection('worker_entries')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false);

  if (projectId != null && projectId.isNotEmpty) {
    query = query.where('projectId', isEqualTo: projectId);
  }

  return query
      .orderBy('date', descending: true)
      .limit(500)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => WorkerEntryRecord.fromMap(doc.id, doc.data()))
            .toList(),
      );
});

final reportWorkersProvider = StreamProvider<List<WorkerProfile>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('workers')
      .where('workspaceId', isEqualTo: workspaceId)
      .where('isArchived', isEqualTo: false)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((doc) => WorkerProfile.fromMap(doc.id, doc.data()))
            .toList(),
      );
});

// ─── Aggregated data ────────────────────────────────────────────────

/// Expense totals grouped by category.
final expensesByCategoryProvider =
    Provider<AsyncValue<Map<String, double>>>((ref) {
  return ref.watch(reportExpensesProvider).whenData((expenses) {
    final map = <String, double>{};
    for (final e in expenses) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  });
});

/// Monthly income vs total expenses (expenses + labor) for last 6 months.
final monthlyFlowProvider =
    Provider<AsyncValue<List<MonthlyFlowData>>>((ref) {
  final expensesAsync = ref.watch(reportExpensesProvider);
  final paymentsAsync = ref.watch(reportPaymentsProvider);
  final entriesAsync = ref.watch(reportWorkerEntriesProvider);

  if (expensesAsync is AsyncLoading ||
      paymentsAsync is AsyncLoading ||
      entriesAsync is AsyncLoading) {
    return const AsyncValue.loading();
  }
  if (expensesAsync is AsyncError) {
    return AsyncValue.error(
      (expensesAsync as AsyncError).error,
      (expensesAsync as AsyncError).stackTrace,
    );
  }

  final expenses = expensesAsync.valueOrNull ?? [];
  final payments = paymentsAsync.valueOrNull ?? [];
  final entries = entriesAsync.valueOrNull ?? [];

  final now = DateTime.now();
  final result = <MonthlyFlowData>[];

  for (int i = 5; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);

    final monthExpenses = expenses
        .where((e) =>
            e.date.isAfter(month.subtract(const Duration(seconds: 1))) &&
            e.date.isBefore(nextMonth))
        .fold<double>(0, (sum, e) => sum + e.amount);

    final monthLabor = entries
        .where((e) =>
            e.date.isAfter(month.subtract(const Duration(seconds: 1))) &&
            e.date.isBefore(nextMonth))
        .fold<double>(0, (sum, e) => sum + e.totalCost);

    final monthIncome = payments
        .where((p) =>
            p.date.isAfter(month.subtract(const Duration(seconds: 1))) &&
            p.date.isBefore(nextMonth))
        .fold<double>(0, (sum, p) => sum + p.amount);

    result.add(MonthlyFlowData(
      month: month,
      expenses: monthExpenses + monthLabor,
      income: monthIncome,
    ));
  }

  return AsyncValue.data(result);
});

/// Top workers by total labor cost.
final topWorkersProvider =
    Provider<AsyncValue<List<WorkerCostData>>>((ref) {
  final entriesAsync = ref.watch(reportWorkerEntriesProvider);
  final workersAsync = ref.watch(reportWorkersProvider);

  if (entriesAsync is AsyncLoading || workersAsync is AsyncLoading) {
    return const AsyncValue.loading();
  }

  final entries = entriesAsync.valueOrNull ?? [];
  final workers = workersAsync.valueOrNull ?? [];
  final workerMap = {for (final w in workers) w.id: w.name};

  final costMap = <String, double>{};
  final daysMap = <String, double>{};
  for (final e in entries) {
    costMap[e.workerId] = (costMap[e.workerId] ?? 0) + e.totalCost;
    daysMap[e.workerId] = (daysMap[e.workerId] ?? 0) + e.daysWorked;
  }

  final result = costMap.entries.map((entry) {
    return WorkerCostData(
      name: workerMap[entry.key] ?? entry.key,
      totalCost: entry.value,
      totalDays: daysMap[entry.key] ?? 0,
    );
  }).toList()
    ..sort((a, b) => b.totalCost.compareTo(a.totalCost));

  return AsyncValue.data(result.take(5).toList());
});

/// Financial summary for the report.
final reportSummaryProvider = Provider<AsyncValue<Map<String, num>>>((ref) {
  final projectId = ref.watch(reportProjectIdProvider);
  if (projectId == null || projectId.isEmpty) {
    return const AsyncValue.data({});
  }

  // Project-specific calculation
  final expensesAsync = ref.watch(reportExpensesProvider);
  final paymentsAsync = ref.watch(reportPaymentsProvider);
  final entriesAsync = ref.watch(reportWorkerEntriesProvider);

  if (expensesAsync is AsyncLoading ||
      paymentsAsync is AsyncLoading ||
      entriesAsync is AsyncLoading) {
    return const AsyncValue.loading();
  }

  if (expensesAsync is AsyncError) return AsyncValue.error(expensesAsync.error!, expensesAsync.stackTrace!);
  if (paymentsAsync is AsyncError) return AsyncValue.error(paymentsAsync.error!, paymentsAsync.stackTrace!);
  if (entriesAsync is AsyncError) return AsyncValue.error(entriesAsync.error!, entriesAsync.stackTrace!);

  final expenses = expensesAsync.valueOrNull ?? [];
  final payments = paymentsAsync.valueOrNull ?? [];
  final entries = entriesAsync.valueOrNull ?? [];

  final totalExpenses = expenses.fold<num>(0, (sum, e) => sum + e.amount);
  final totalLabor = entries.fold<num>(0, (sum, e) => sum + e.totalCost);
  final totalIncome = payments.fold<num>(0, (sum, p) => sum + p.amount);

  final totalOut = totalExpenses + totalLabor;

  return AsyncValue.data({
    'totalExpenses': totalOut,
    'totalIncome': totalIncome,
    'net': totalIncome - totalOut,
    'totalProjects': 1,
    'activeProjects': 1, // Assumptions for single project
  });
});

// ─── Data classes ───────────────────────────────────────────────────

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
