import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';

enum ReportExportStage { expenses, payments, complete }

class ReportExportCancelled implements Exception {
  const ReportExportCancelled();
}

class ReportExportProgress {
  const ReportExportProgress({
    required this.stage,
    required this.loadedRecords,
  });

  final ReportExportStage stage;
  final int loadedRecords;
}

typedef ReportExportProgressCallback =
    void Function(ReportExportProgress progress);
typedef ReportExportCancellationCheck = bool Function();

class ReportExportData {
  const ReportExportData({
    required this.expenses,
    required this.payments,
    required this.entitySummaries,
    required this.insights,
  });

  final List<Expense> expenses;
  final List<PaymentRecord> payments;
  final List<EntitySummary> entitySummaries;
  final DashboardWeeklyInsights insights;
}

class ReportExportDataBuilder {
  const ReportExportDataBuilder({
    required ExpenseRepository expenseRepository,
    required PaymentRepository paymentRepository,
  }) : _expenseRepository = expenseRepository,
       _paymentRepository = paymentRepository;

  static const int pageSize = 500;

  final ExpenseRepository _expenseRepository;
  final PaymentRepository _paymentRepository;

  Future<ReportExportData> build({
    required String workspaceId,
    required String projectId,
    required DateTime startDate,
    required DateTime endDate,
    required bool includeExpenses,
    required bool includePayments,
    required bool includeEntities,
    required bool includeDaily,
    required bool includeWeekly,
    ReportExportProgressCallback? onProgress,
    ReportExportCancellationCheck? isCancelled,
  }) async {
    _throwIfCancelled(isCancelled);
    final shouldFetchExpenses =
        includeExpenses || includeEntities || includeDaily || includeWeekly;
    final shouldFetchPayments =
        includePayments || includeEntities || includeWeekly;

    final expenses = shouldFetchExpenses
        ? await _fetchAllExpenses(
            workspaceId: workspaceId,
            projectId: projectId,
            startDate: startDate,
            endDate: endDate,
            onProgress: onProgress,
            isCancelled: isCancelled,
          )
        : const <Expense>[];
    final payments = shouldFetchPayments
        ? await _fetchAllPayments(
            workspaceId: workspaceId,
            projectId: projectId,
            startDate: startDate,
            endDate: endDate,
            onProgress: onProgress,
            isCancelled: isCancelled,
          )
        : const <PaymentRecord>[];

    final filteredExpenses = expenses
        .where(
          (expense) =>
              expense.projectId == projectId &&
              !expense.date.isBefore(startDate) &&
              !expense.date.isAfter(endDate),
        )
        .toList(growable: false);
    final filteredPayments = payments
        .where(
          (payment) =>
              payment.projectId == projectId &&
              !payment.date.isBefore(startDate) &&
              !payment.date.isAfter(endDate),
        )
        .toList(growable: false);

    final result = ReportExportData(
      expenses: filteredExpenses,
      payments: filteredPayments,
      entitySummaries: includeEntities
          ? _buildEntitySummaries(filteredExpenses, filteredPayments)
          : const <EntitySummary>[],
      insights: includeWeekly
          ? _buildWeeklyInsights(filteredExpenses, filteredPayments)
          : _emptyInsights(),
    );
    onProgress?.call(
      ReportExportProgress(
        stage: ReportExportStage.complete,
        loadedRecords: filteredExpenses.length + filteredPayments.length,
      ),
    );
    return result;
  }

  Future<List<Expense>> _fetchAllExpenses({
    required String workspaceId,
    required String projectId,
    required DateTime startDate,
    required DateTime endDate,
    ReportExportProgressCallback? onProgress,
    ReportExportCancellationCheck? isCancelled,
  }) async {
    final items = <Expense>[];
    Object? cursor;

    while (true) {
      _throwIfCancelled(isCancelled);
      final page = await _expenseRepository.fetchExpensesPage(
        workspaceId,
        projectId: projectId,
        startDate: startDate,
        endDate: endDate,
        cursor: cursor,
        pageSize: pageSize,
      );
      items.addAll(page.items);
      onProgress?.call(
        ReportExportProgress(
          stage: ReportExportStage.expenses,
          loadedRecords: items.length,
        ),
      );
      _throwIfCancelled(isCancelled);
      if (!page.hasMore || page.nextCursor == null) {
        break;
      }
      cursor = page.nextCursor;
    }

    return items;
  }

  Future<List<PaymentRecord>> _fetchAllPayments({
    required String workspaceId,
    required String projectId,
    required DateTime startDate,
    required DateTime endDate,
    ReportExportProgressCallback? onProgress,
    ReportExportCancellationCheck? isCancelled,
  }) async {
    final items = <PaymentRecord>[];
    Object? cursor;

    while (true) {
      _throwIfCancelled(isCancelled);
      final page = await _paymentRepository.fetchPaymentsPage(
        workspaceId,
        projectId: projectId,
        startDate: startDate,
        endDate: endDate,
        cursor: cursor,
        pageSize: pageSize,
      );
      items.addAll(page.items);
      onProgress?.call(
        ReportExportProgress(
          stage: ReportExportStage.payments,
          loadedRecords: items.length,
        ),
      );
      _throwIfCancelled(isCancelled);
      if (!page.hasMore || page.nextCursor == null) {
        break;
      }
      cursor = page.nextCursor;
    }

    return items;
  }

  void _throwIfCancelled(ReportExportCancellationCheck? isCancelled) {
    if (isCancelled?.call() == true) {
      throw const ReportExportCancelled();
    }
  }

  List<EntitySummary> _buildEntitySummaries(
    List<Expense> expenses,
    List<PaymentRecord> payments,
  ) {
    final summaries = <String, EntitySummary>{};

    void upsert({
      required String key,
      required String name,
      required String type,
      required double expenseAmount,
      required double paymentAmount,
      required int attachmentCount,
      required DateTime date,
    }) {
      final summary = summaries.putIfAbsent(
        key,
        () => EntitySummary(entityId: key, entityName: name, entityType: type),
      );
      summary.totalExpenses += expenseAmount;
      summary.totalPayments += paymentAmount;
      summary.transactionCount += 1;
      summary.attachmentCount += attachmentCount;
      if (summary.latestTransaction == null ||
          date.isAfter(summary.latestTransaction!)) {
        summary.latestTransaction = date;
      }
    }

    for (final expense in expenses) {
      final name = expense.entityName.isNotEmpty
          ? expense.entityName
          : expense.supplierName;
      final key = expense.entityId?.trim().isNotEmpty == true
          ? expense.entityId!
          : (name.isNotEmpty ? name : 'unassigned');
      upsert(
        key: key,
        name: name.isNotEmpty ? name : 'Unassigned',
        type: expense.entityType.isNotEmpty ? expense.entityType : 'supplier',
        expenseAmount: expense.amount,
        paymentAmount: 0,
        attachmentCount: expense.attachments.length,
        date: expense.date,
      );
    }

    for (final payment in payments) {
      final name = payment.entityName.isNotEmpty
          ? payment.entityName
          : 'Unassigned';
      final key = payment.entityId?.trim().isNotEmpty == true
          ? payment.entityId!
          : (payment.entityName.isNotEmpty ? payment.entityName : 'unassigned');
      upsert(
        key: key,
        name: name,
        type: payment.entityType.isNotEmpty ? payment.entityType : 'other',
        expenseAmount: 0,
        paymentAmount: payment.cashCollected,
        attachmentCount: payment.attachments.length,
        date: payment.date,
      );
    }

    final result = summaries.values.toList(growable: false)
      ..sort((a, b) {
        final latestCompare = (b.latestTransaction ?? DateTime(0)).compareTo(
          a.latestTransaction ?? DateTime(0),
        );
        if (latestCompare != 0) {
          return latestCompare;
        }
        return (b.totalExpenses + b.totalPayments).compareTo(
          a.totalExpenses + a.totalPayments,
        );
      });
    return result;
  }

  DashboardWeeklyInsights _buildWeeklyInsights(
    List<Expense> expenses,
    List<PaymentRecord> payments,
  ) {
    final categoryTotals = <String, double>{};
    final entityTotals = <String, double>{};
    final paymentTotals = <String, double>{};
    var laborTotal = 0.0;
    var equipmentTotal = 0.0;
    final recent = <WeeklyDashboardTransaction>[];

    for (final expense in expenses) {
      final category = expense.category.trim().isEmpty
          ? 'unassigned'
          : expense.category;
      final entityName = expense.entityName.isNotEmpty
          ? expense.entityName
          : (expense.supplierName.isNotEmpty
                ? expense.supplierName
                : 'unassigned');
      final paymentMethod = expense.paymentMethod.trim().isEmpty
          ? 'Unknown'
          : expense.paymentMethod;

      categoryTotals[category] =
          (categoryTotals[category] ?? 0) + expense.amount;
      entityTotals[entityName] =
          (entityTotals[entityName] ?? 0) + expense.amount;
      paymentTotals[paymentMethod] =
          (paymentTotals[paymentMethod] ?? 0) + expense.amount;
      if (category == 'labor') {
        laborTotal += expense.amount;
      }
      if (category == 'equipment') {
        equipmentTotal += expense.amount;
      }
      recent.add(
        WeeklyDashboardTransaction(
          title: entityName,
          amount: expense.amount,
          date: expense.date,
          type: 'expense',
        ),
      );
    }

    for (final payment in payments) {
      final entityName = payment.entityName.isNotEmpty
          ? payment.entityName
          : 'unassigned';
      final paymentMethod = payment.paymentMethod.trim().isEmpty
          ? 'Unknown'
          : payment.paymentMethod;

      entityTotals[entityName] =
          (entityTotals[entityName] ?? 0) + payment.cashCollected;
      paymentTotals[paymentMethod] =
          (paymentTotals[paymentMethod] ?? 0) + payment.cashCollected;
      recent.add(
        WeeklyDashboardTransaction(
          title: entityName,
          amount: payment.cashCollected,
          date: payment.date,
          type: 'payment',
        ),
      );
    }

    String topKey(Map<String, double> totals) {
      String key = 'unassigned';
      var value = 0.0;
      for (final entry in totals.entries) {
        if (entry.value > value && entry.key.trim().isNotEmpty) {
          key = entry.key;
          value = entry.value;
        }
      }
      return key;
    }

    recent.sort((a, b) => b.date.compareTo(a.date));

    return DashboardWeeklyInsights(
      topEntity: topKey(entityTotals),
      topCategory: topKey(categoryTotals),
      laborTotal: laborTotal,
      equipmentTotal: equipmentTotal,
      paymentSummary: paymentTotals,
      recentTransactions: recent.take(5).toList(growable: false),
    );
  }

  DashboardWeeklyInsights _emptyInsights() {
    return DashboardWeeklyInsights(
      topEntity: 'unassigned',
      topCategory: 'unassigned',
      laborTotal: 0,
      equipmentTotal: 0,
      paymentSummary: const {},
      recentTransactions: const [],
    );
  }
}
