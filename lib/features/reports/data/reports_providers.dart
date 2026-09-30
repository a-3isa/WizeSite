import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/contractors/domain/contractor_accounting_record.dart';
import 'package:buildtrack_app/features/equipment/domain/equipment_accounting_record.dart';
import 'package:buildtrack_app/features/transport/domain/transport_provider_accounting_record.dart';
import 'package:buildtrack_app/features/workers/domain/worker_accounting_record.dart';
import 'package:buildtrack_app/features/reports/domain/report_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final reportProjectIdProvider = StateProvider<String?>((ref) => null);
final reportNowProvider = Provider<DateTime>((ref) => DateTime.now());
final reportScopeProvider = StateProvider<ReportScope>(
  (ref) => ReportScope.monthToDate(now: ref.watch(reportNowProvider)),
);
final effectiveReportScopeProvider = Provider<ReportScope>((ref) {
  final scope = ref.watch(reportScopeProvider);
  final legacyProjectId = ref.watch(reportProjectIdProvider);
  if (scope.hasProject || legacyProjectId == null || legacyProjectId.isEmpty) {
    return scope;
  }
  return scope.copyWith(projectId: legacyProjectId);
});

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

class ReportScopedRows {
  const ReportScopedRows({
    required this.expenses,
    required this.payments,
    required this.hasMore,
  });

  final List<Expense> expenses;
  final List<PaymentRecord> payments;
  final bool hasMore;
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
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => Expense.fromMap(
              '${item['id'] ?? ''}',
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    }

    List<PaymentRecord> payments = const [];
    final rawPayments = map['recentPayments'];
    if (rawPayments is List) {
      payments = rawPayments
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => PaymentRecord.fromMap(
              '${item['id'] ?? ''}',
              Map<String, dynamic>.from(item),
            ),
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
    final payloadProjectId = '${action.payload['projectId'] ?? ''}';
    final previousProjectId = '${action.payload['previousProjectId'] ?? ''}';
    if (payloadProjectId != projectId && previousProjectId != projectId) {
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
        final previousAmount = ((action.payload['previousAmount'] as num?) ?? 0)
            .toDouble();
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
          expenses: point.expenses + ((action.payload['amount'] as num?) ?? 0),
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
      case OfflineActionTypes.updateWorkerEntry:
        final previousProjectId =
            '${action.payload['previousProjectId'] ?? projectId}';
        final previousDate = _parsePendingDate(action.payload['previousDate']);
        final previousCost =
            ((action.payload['previousTotalCost'] as num?)?.toDouble() ??
            (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                    ((action.payload['previousDailyWage'] as num?) ?? 0))
                .toDouble());
        if (previousProjectId == projectId && previousDate != null) {
          final previousPoint = pointFor(previousDate);
          points[_monthKey(previousPoint.month)] = MonthlyFlowData(
            month: previousPoint.month,
            expenses: previousPoint.expenses - previousCost,
            income: previousPoint.income,
          );
        }
        if ('${action.payload['projectId'] ?? ''}' == projectId) {
          final nextCost =
              ((action.payload['totalCost'] as num?)?.toDouble() ??
              (((action.payload['daysWorked'] as num?) ?? 0) *
                      ((action.payload['dailyWage'] as num?) ?? 0))
                  .toDouble());
          points[_monthKey(point.month)] = MonthlyFlowData(
            month: point.month,
            expenses: point.expenses + nextCost,
            income: point.income,
          );
        }
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
        final previousAmount = ((action.payload['previousAmount'] as num?) ?? 0)
            .toDouble();
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
  final totals = <String, double>{};

  // `labor` is deprecated and merged into `worker`; server recompute already
  // keys labor cost as `worker`, so fold legacy keys from either side into it.
  void addToCategory(String category, double delta) {
    final key = category == AccountingCategories.labor
        ? AccountingCategories.worker
        : category;
    final nextValue = (totals[key] ?? 0) + delta;
    if (nextValue == 0) {
      totals.remove(key);
      return;
    }
    totals[key] = nextValue;
  }

  base.forEach(addToCategory);

  for (final action in actions) {
    final payloadProjectId = '${action.payload['projectId'] ?? ''}';
    final previousProjectId = '${action.payload['previousProjectId'] ?? ''}';
    if (payloadProjectId != projectId && previousProjectId != projectId) {
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
        if ('${action.payload['projectId'] ?? ''}' == projectId) {
          addToCategory(
            AccountingCategories.worker,
            ((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                        ((action.payload['dailyWage'] as num?) ?? 0))
                    .toDouble()),
          );
        }
        break;
      case OfflineActionTypes.archiveWorkerEntry:
        addToCategory(
          AccountingCategories.worker,
          -((action.payload['totalCost'] as num?)?.toDouble() ??
              (((action.payload['daysWorked'] as num?) ?? 0) *
                      ((action.payload['dailyWage'] as num?) ?? 0))
                  .toDouble()),
        );
        break;
      case OfflineActionTypes.updateWorkerEntry:
        final previousProjectId =
            '${action.payload['previousProjectId'] ?? projectId}';
        if (previousProjectId == projectId) {
          addToCategory(
            AccountingCategories.worker,
            -((action.payload['previousTotalCost'] as num?)?.toDouble() ??
                (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                        ((action.payload['previousDailyWage'] as num?) ?? 0))
                    .toDouble()),
          );
        }
        if ('${action.payload['projectId'] ?? ''}' == projectId) {
          addToCategory(
            AccountingCategories.worker,
            ((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                        ((action.payload['dailyWage'] as num?) ?? 0))
                    .toDouble()),
          );
        }
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

  for (final action in actions) {
    if (action.type != OfflineActionTypes.updateExpense ||
        '${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    final expenseId = '${action.payload['expenseId'] ?? ''}';
    final index = items.indexWhere((item) => item.id == expenseId);
    if (index < 0) {
      continue;
    }
    final current = items[index];
    items[index] = Expense(
      id: current.id,
      workspaceId: current.workspaceId,
      projectId: current.projectId,
      projectName: current.projectName,
      category: '${action.payload['category'] ?? current.category}',
      amount: (action.payload['amount'] as num?)?.toDouble() ?? current.amount,
      currency: current.currency,
      date: _parsePendingDate(action.payload['date']) ?? current.date,
      notes: '${action.payload['notes'] ?? current.notes}',
      supplierName: '${action.payload['supplierName'] ?? current.supplierName}',
      paymentMethod:
          '${action.payload['paymentMethod'] ?? current.paymentMethod}',
      inputMethod: current.inputMethod,
      transcript: current.transcript,
      source: current.source,
      storagePath: current.storagePath,
      attachments: current.attachments,
      isArchived: current.isArchived,
      clientMutationId: current.clientMutationId,
    );
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
        attachments: Attachment.listFromDynamic(action.payload['attachments']),
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

  for (final action in actions) {
    if (action.type != OfflineActionTypes.updatePayment ||
        '${action.payload['projectId'] ?? ''}' != projectId) {
      continue;
    }
    final paymentId = '${action.payload['paymentId'] ?? ''}';
    final index = items.indexWhere((item) => item.id == paymentId);
    if (index < 0) {
      continue;
    }
    final current = items[index];
    items[index] = PaymentRecord(
      id: current.id,
      workspaceId: current.workspaceId,
      projectId: current.projectId,
      amount: (action.payload['amount'] as num?)?.toDouble() ?? current.amount,
      date: _parsePendingDate(action.payload['date']) ?? current.date,
      paymentMethod:
          '${action.payload['paymentMethod'] ?? current.paymentMethod}',
      notes: '${action.payload['notes'] ?? current.notes}',
      attachments: current.attachments,
      isArchived: current.isArchived,
      clientMutationId: current.clientMutationId,
    );
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
        attachments: Attachment.listFromDynamic(action.payload['attachments']),
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
  final candidateActions = actions
      .where((action) {
        final payloadProjectId = '${action.payload['projectId'] ?? ''}';
        final previousProjectId =
            '${action.payload['previousProjectId'] ?? ''}';
        return payloadProjectId == projectId || previousProjectId == projectId;
      })
      .toList(growable: false);
  if (base == null) {
    if (candidateActions.isEmpty) {
      return null;
    }

    final projectName = candidateActions
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
  final relevantActions = <OfflineAction>[];
  for (final action in candidateActions) {
    final delta = _reportDeltaForAction(action, projectId);
    final expenseReflected = _isReportDeltaAlreadyReflected(
      action: action,
      baselineField: 'projectTotalExpensesBefore',
      currentTotal: totalExpenses,
      delta: delta.expenses,
    );
    final incomeReflected = _isReportDeltaAlreadyReflected(
      action: action,
      baselineField: 'projectTotalPaymentsBefore',
      currentTotal: totalIncome,
      delta: delta.income,
    );
    if (expenseReflected && incomeReflected) {
      continue;
    }
    relevantActions.add(action);
    switch (action.type) {
      case OfflineActionTypes.createExpense:
        totalExpenses += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.archiveExpense:
        totalExpenses -= ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.updateExpense:
        totalExpenses -= ((action.payload['previousAmount'] as num?) ?? 0)
            .toDouble();
        totalExpenses += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.createWorkerEntry:
        if ('${action.payload['projectId'] ?? ''}' == projectId) {
          totalExpenses +=
              ((action.payload['totalCost'] as num?)?.toDouble() ??
              (((action.payload['daysWorked'] as num?) ?? 0) *
                      ((action.payload['dailyWage'] as num?) ?? 0))
                  .toDouble());
        }
        break;
      case OfflineActionTypes.archiveWorkerEntry:
        totalExpenses -=
            ((action.payload['totalCost'] as num?)?.toDouble() ??
            (((action.payload['daysWorked'] as num?) ?? 0) *
                    ((action.payload['dailyWage'] as num?) ?? 0))
                .toDouble());
        break;
      case OfflineActionTypes.updateWorkerEntry:
        final previousProjectId =
            '${action.payload['previousProjectId'] ?? projectId}';
        if (previousProjectId == projectId) {
          totalExpenses -=
              ((action.payload['previousTotalCost'] as num?)?.toDouble() ??
              (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                      ((action.payload['previousDailyWage'] as num?) ?? 0))
                  .toDouble());
        }
        if ('${action.payload['projectId'] ?? ''}' == projectId) {
          totalExpenses +=
              ((action.payload['totalCost'] as num?)?.toDouble() ??
              (((action.payload['daysWorked'] as num?) ?? 0) *
                      ((action.payload['dailyWage'] as num?) ?? 0))
                  .toDouble());
        }
        break;
      case OfflineActionTypes.createPayment:
        totalIncome += ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.archivePayment:
        totalIncome -= ((action.payload['amount'] as num?) ?? 0).toDouble();
        break;
      case OfflineActionTypes.updatePayment:
        totalIncome -= ((action.payload['previousAmount'] as num?) ?? 0)
            .toDouble();
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
    categoryTotals: _mergeCategoryTotals(
      base.categoryTotals,
      relevantActions,
      projectId,
    ),
    monthlyFlow: _mergeMonthlyFlow(
      base.monthlyFlow,
      relevantActions,
      projectId,
    ),
    topWorkers: base.topWorkers,
    recentExpenses: _mergeRecentExpenses(
      base.recentExpenses,
      relevantActions,
      projectId,
    ),
    recentPayments: _mergeRecentPayments(
      base.recentPayments,
      relevantActions,
      projectId,
    ),
  );
}

({double expenses, double income}) _reportDeltaForAction(
  OfflineAction action,
  String projectId,
) {
  switch (action.type) {
    case OfflineActionTypes.createExpense:
      return (
        expenses: ((action.payload['amount'] as num?) ?? 0).toDouble(),
        income: 0,
      );
    case OfflineActionTypes.archiveExpense:
      return (
        expenses: -((action.payload['amount'] as num?) ?? 0).toDouble(),
        income: 0,
      );
    case OfflineActionTypes.updateExpense:
      return (
        expenses:
            (((action.payload['amount'] as num?) ?? 0) -
                    ((action.payload['previousAmount'] as num?) ?? 0))
                .toDouble(),
        income: 0,
      );
    case OfflineActionTypes.createWorkerEntry:
      if ('${action.payload['projectId'] ?? ''}' != projectId) {
        return (expenses: 0, income: 0);
      }
      return (
        expenses:
            ((action.payload['totalCost'] as num?)?.toDouble() ??
            (((action.payload['daysWorked'] as num?) ?? 0) *
                    ((action.payload['dailyWage'] as num?) ?? 0))
                .toDouble()),
        income: 0,
      );
    case OfflineActionTypes.archiveWorkerEntry:
      return (
        expenses:
            -((action.payload['totalCost'] as num?)?.toDouble() ??
                (((action.payload['daysWorked'] as num?) ?? 0) *
                        ((action.payload['dailyWage'] as num?) ?? 0))
                    .toDouble()),
        income: 0,
      );
    case OfflineActionTypes.updateWorkerEntry:
      final previousProjectId =
          '${action.payload['previousProjectId'] ?? projectId}';
      var expenses = 0.0;
      if (previousProjectId == projectId) {
        expenses -=
            ((action.payload['previousTotalCost'] as num?)?.toDouble() ??
            (((action.payload['previousDaysWorked'] as num?) ?? 0) *
                    ((action.payload['previousDailyWage'] as num?) ?? 0))
                .toDouble());
      }
      if ('${action.payload['projectId'] ?? ''}' == projectId) {
        expenses +=
            ((action.payload['totalCost'] as num?)?.toDouble() ??
            (((action.payload['daysWorked'] as num?) ?? 0) *
                    ((action.payload['dailyWage'] as num?) ?? 0))
                .toDouble());
      }
      return (expenses: expenses, income: 0);
    case OfflineActionTypes.createPayment:
      return (
        expenses: 0,
        income: ((action.payload['amount'] as num?) ?? 0).toDouble(),
      );
    case OfflineActionTypes.archivePayment:
      return (
        expenses: 0,
        income: -((action.payload['amount'] as num?) ?? 0).toDouble(),
      );
    case OfflineActionTypes.updatePayment:
      return (
        expenses: 0,
        income:
            (((action.payload['amount'] as num?) ?? 0) -
                    ((action.payload['previousAmount'] as num?) ?? 0))
                .toDouble(),
      );
    default:
      return (expenses: 0, income: 0);
  }
}

bool _isReportDeltaAlreadyReflected({
  required OfflineAction action,
  required String baselineField,
  required double currentTotal,
  required double delta,
}) {
  final baseline = (action.payload[baselineField] as num?)?.toDouble();
  if (baseline == null || delta == 0) {
    return delta == 0;
  }
  final expected =
      (action.payload[baselineField.replaceFirst('Before', 'After')] as num?)
          ?.toDouble() ??
      baseline + delta;
  return delta > 0 ? currentTotal >= expected : currentTotal <= expected;
}

final reportScopedRowsProvider = FutureProvider<ReportScopedRows?>((ref) async {
  final role = await ref.watch(currentAccountingRoleProvider.future);
  if (role?.canAccessAccounting != true) {
    return null;
  }
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final scope = ref.watch(effectiveReportScopeProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return null;
  }

  // Portfolio (all-projects) rollup: aggregate workspace-wide rows in range.
  // Backed by the existing (workspaceId, isArchived, date) composite indexes.
  if (!scope.hasProject) {
    final source = ref.watch(docSourceProvider);
    const limit = 1000;
    final results = await Future.wait([
      source.get(
        DocQuery(
          'expenses',
          equals: {'workspaceId': workspaceId, 'isArchived': false},
          rangeField: 'date',
          rangeFrom: scope.startDate,
          rangeTo: scope.endDate,
          orderBy: 'date',
          descending: true,
          limit: limit,
        ),
      ),
      source.get(
        DocQuery(
          'payments',
          equals: {'workspaceId': workspaceId, 'isArchived': false},
          rangeField: 'date',
          rangeFrom: scope.startDate,
          rangeTo: scope.endDate,
          orderBy: 'date',
          descending: true,
          limit: limit,
        ),
      ),
    ]);
    final allExpenses =
        results[0]
            .map((doc) => Expense.fromMap(doc.id, doc.data))
            .where((item) => scope.contains(item.date))
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    final allPayments =
        results[1]
            .map((doc) => PaymentRecord.fromMap(doc.id, doc.data))
            .where((item) => scope.contains(item.date))
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    return ReportScopedRows(
      expenses: allExpenses,
      payments: allPayments,
      hasMore: results[0].length >= limit || results[1].length >= limit,
    );
  }

  final expenseFuture = ref
      .watch(expenseRepositoryProvider)
      .fetchExpensesPage(
        workspaceId,
        projectId: scope.projectId!,
        startDate: scope.startDate,
        endDate: scope.endDate,
        cursor: null,
        pageSize: 500,
      );
  final paymentFuture = ref
      .watch(paymentRepositoryProvider)
      .fetchPaymentsPage(
        workspaceId,
        projectId: scope.projectId!,
        startDate: scope.startDate,
        endDate: scope.endDate,
        cursor: null,
        pageSize: 500,
      );
  final expensePage = await expenseFuture;
  final paymentPage = await paymentFuture;

  final expenses =
      expensePage.items
          .where(
            (item) =>
                item.projectId == scope.projectId && scope.contains(item.date),
          )
          .toList(growable: false)
        ..sort((a, b) => b.date.compareTo(a.date));
  final payments =
      paymentPage.items
          .where(
            (item) =>
                item.projectId == scope.projectId && scope.contains(item.date),
          )
          .toList(growable: false)
        ..sort((a, b) => b.date.compareTo(a.date));
  return ReportScopedRows(
    expenses: expenses,
    payments: payments,
    hasMore: expensePage.hasMore || paymentPage.hasMore,
  );
});

ReportMetrics _metricsFromScopedRows(
  ReportMetrics? base,
  ReportScope scope,
  ReportScopedRows rows,
) {
  final categoryTotals = <String, double>{};
  final monthly = <String, MonthlyFlowData>{};

  MonthlyFlowData monthFor(DateTime date) {
    final key = _monthKey(date);
    return monthly.putIfAbsent(
      key,
      () => MonthlyFlowData(
        month: DateTime.utc(date.year, date.month),
        expenses: 0,
        income: 0,
      ),
    );
  }

  var totalExpenses = 0.0;
  for (final expense in rows.expenses) {
    totalExpenses += expense.amount;
    categoryTotals.update(
      expense.category,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
    final point = monthFor(expense.date);
    monthly[_monthKey(point.month)] = MonthlyFlowData(
      month: point.month,
      expenses: point.expenses + expense.amount,
      income: point.income,
    );
  }

  var totalIncome = 0.0;
  for (final payment in rows.payments) {
    final cashIn = payment.cashCollected;
    totalIncome += cashIn;
    final point = monthFor(payment.date);
    monthly[_monthKey(point.month)] = MonthlyFlowData(
      month: point.month,
      expenses: point.expenses,
      income: point.income + cashIn,
    );
  }

  final monthlyFlow = monthly.values.toList(growable: false)
    ..sort((a, b) => a.month.compareTo(b.month));
  return ReportMetrics(
    projectId: scope.projectId ?? '',
    projectName: base?.projectName ?? '',
    status: base?.status ?? 'active',
    isArchived: base?.isArchived ?? false,
    totalExpenses: totalExpenses,
    totalIncome: totalIncome,
    net: totalIncome - totalExpenses,
    categoryTotals: categoryTotals,
    monthlyFlow: monthlyFlow,
    topWorkers: const [],
    recentExpenses: rows.expenses.take(5).toList(growable: false),
    recentPayments: rows.payments.take(5).toList(growable: false),
  );
}

final reportBaseMetricsProvider = StreamProvider<ReportMetrics?>((ref) {
  final projectId = ref.watch(effectiveReportScopeProvider).projectId;
  if (projectId == null || projectId.isEmpty) {
    return Stream.value(null);
  }
  final source = ref.watch(docSourceProvider);
  return (() async* {
    final role = await ref.watch(currentAccountingRoleProvider.future);
    if (role?.canAccessAccounting != true) {
      yield null;
      return;
    }
    yield* source.watchDoc('project_metrics', projectId).map((snap) {
      if (snap == null) {
        return null;
      }
      return ReportMetrics.fromMap(snap.id, snap.data);
    });
  })();
});

final reportPendingActionsProvider = StreamProvider<List<OfflineAction>>((ref) {
  return ref
      .watch(offlineActionQueueProvider)
      .watch(includeExpiredSynced: true);
});

final reportMetricsProvider = Provider<AsyncValue<ReportMetrics?>>((ref) {
  final scope = ref.watch(effectiveReportScopeProvider);

  final baseAsync = ref.watch(reportBaseMetricsProvider);
  final pendingAsync = ref.watch(reportPendingActionsProvider);
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final scopedRowsAsync = workspaceId == null || workspaceId.isEmpty
      ? const AsyncData<ReportScopedRows?>(null)
      : ref.watch(reportScopedRowsProvider);

  return baseAsync.when(
    data: (base) => pendingAsync.when(
      data: (actions) => scopedRowsAsync.when(
        data: (rows) {
          // Portfolio (all-projects) rollup: derive purely from the
          // workspace-wide rows; there is no single project to merge against.
          if (!scope.hasProject) {
            return AsyncData(
              rows == null ? null : _metricsFromScopedRows(null, scope, rows),
            );
          }
          final merged = _mergePendingActionsIntoMetrics(
            base,
            actions,
            scope.projectId!,
          );
          return AsyncData(
            rows == null ? merged : _metricsFromScopedRows(merged, scope, rows),
          );
        },
        error: (error, stackTrace) => AsyncError(error, stackTrace),
        loading: () => const AsyncLoading(),
      ),
      error: (error, stackTrace) => AsyncError(error, stackTrace),
      loading: () => const AsyncLoading(),
    ),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
    loading: () => const AsyncLoading(),
  );
});

final reportExpensesProvider = Provider<AsyncValue<List<Expense>>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final scopedRows = workspaceId == null || workspaceId.isEmpty
      ? const AsyncData<ReportScopedRows?>(null)
      : ref.watch(reportScopedRowsProvider);
  return scopedRows.when(
    data: (rows) => rows == null
        ? ref
              .watch(reportMetricsProvider)
              .whenData((metrics) => metrics?.recentExpenses ?? const [])
        : AsyncData(rows.expenses),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
    loading: () => const AsyncLoading(),
  );
});

final reportPaymentsProvider = Provider<AsyncValue<List<PaymentRecord>>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final scopedRows = workspaceId == null || workspaceId.isEmpty
      ? const AsyncData<ReportScopedRows?>(null)
      : ref.watch(reportScopedRowsProvider);
  return scopedRows.when(
    data: (rows) => rows == null
        ? ref
              .watch(reportMetricsProvider)
              .whenData((metrics) => metrics?.recentPayments ?? const [])
        : AsyncData(rows.payments),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
    loading: () => const AsyncLoading(),
  );
});

Stream<List<T>> _scopedAccountingRecordsStream<T>({
  required Ref ref,
  required String collection,
  required T Function(String id, Map<String, dynamic> data) fromMap,
}) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  final scope = ref.watch(effectiveReportScopeProvider);
  if (workspaceId == null || workspaceId.isEmpty || !scope.hasProject) {
    return Stream.value(List<T>.empty(growable: false));
  }
  final source = ref.watch(docSourceProvider);
  return (() async* {
    final role = await ref.watch(currentAccountingRoleProvider.future);
    if (role?.canAccessAccounting != true) {
      yield List<T>.empty(growable: false);
      return;
    }
    yield* source
        .watch(
          DocQuery(
            collection,
            equals: {'workspaceId': workspaceId, 'projectId': scope.projectId},
            rangeField: 'date',
            rangeFrom: scope.startDate,
            rangeTo: scope.endDate,
            orderBy: 'date',
            descending: true,
            limit: 50,
          ),
        )
        .map(
          (snap) => snap
              .map((doc) => fromMap(doc.id, doc.data))
              .where((record) {
                final date = switch (record) {
                  WorkerAccountingRecord item => item.date,
                  ContractorAccountingRecord item => item.date,
                  EquipmentAccountingRecord item => item.date,
                  TransportProviderAccountingRecord item => item.date,
                  _ => null,
                };
                return date != null && scope.contains(date);
              })
              .toList(growable: false),
        );
  })();
}

final reportWorkerAccountingRecordsProvider =
    StreamProvider<List<WorkerAccountingRecord>>((ref) {
      return _scopedAccountingRecordsStream(
        ref: ref,
        collection: 'worker_accounting_records',
        fromMap: WorkerAccountingRecord.fromMap,
      );
    });

final reportContractorAccountingRecordsProvider =
    StreamProvider<List<ContractorAccountingRecord>>((ref) {
      return _scopedAccountingRecordsStream(
        ref: ref,
        collection: 'contractor_accounting_records',
        fromMap: ContractorAccountingRecord.fromMap,
      );
    });

final reportEquipmentAccountingRecordsProvider =
    StreamProvider<List<EquipmentAccountingRecord>>((ref) {
      return _scopedAccountingRecordsStream(
        ref: ref,
        collection: 'equipment_accounting_records',
        fromMap: EquipmentAccountingRecord.fromMap,
      );
    });

final reportTransportAccountingRecordsProvider =
    StreamProvider<List<TransportProviderAccountingRecord>>((ref) {
      return _scopedAccountingRecordsStream(
        ref: ref,
        collection: 'transport_provider_accounting_records',
        fromMap: TransportProviderAccountingRecord.fromMap,
      );
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
  final recordsAsync = ref.watch(reportWorkerAccountingRecordsProvider);
  return recordsAsync.whenData((records) {
    final totals = <String, WorkerCostData>{};
    for (final record in records) {
      final key = record.workerId.isNotEmpty
          ? record.workerId
          : record.workerName;
      final current = totals[key];
      totals[key] = WorkerCostData(
        name: record.workerName,
        totalCost: (current?.totalCost ?? 0) + record.amount,
        totalDays: current?.totalDays ?? 0,
      );
    }
    final workers = totals.values.toList(growable: false)
      ..sort((a, b) {
        final costCompare = b.totalCost.compareTo(a.totalCost);
        return costCompare != 0 ? costCompare : a.name.compareTo(b.name);
      });
    return workers.take(5).toList(growable: false);
  });
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
