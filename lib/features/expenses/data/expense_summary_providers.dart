import 'dart:async';

import 'package:buildtrack_app/core/models/accounting_summary.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExpenseSummaryScope {
  const ExpenseSummaryScope({
    required this.workspaceId,
    required this.projectId,
    required this.now,
  });

  final String workspaceId;
  final String projectId;
  final DateTime now;

  @override
  bool operator ==(Object other) {
    return other is ExpenseSummaryScope &&
        other.workspaceId == workspaceId &&
        other.projectId == projectId &&
        other.now == now;
  }

  @override
  int get hashCode => Object.hash(workspaceId, projectId, now);
}

class ExpenseQuickSummary {
  const ExpenseQuickSummary({
    this.todayExpenses = 0,
    this.weeklyExpenses = 0,
    this.monthlyExpenses = 0,
    this.transactionCount = 0,
  });

  final double todayExpenses;
  final double weeklyExpenses;
  final double monthlyExpenses;
  final int transactionCount;

  ExpenseQuickSummary copyWithPending({
    required double todayDelta,
    required double weeklyDelta,
    required double monthlyDelta,
    required int transactionDelta,
  }) {
    return ExpenseQuickSummary(
      todayExpenses: todayExpenses + todayDelta,
      weeklyExpenses: weeklyExpenses + weeklyDelta,
      monthlyExpenses: monthlyExpenses + monthlyDelta,
      transactionCount: transactionCount + transactionDelta,
    );
  }

  factory ExpenseQuickSummary.fromProjectSummary(
    ProjectAccountingSummary summary,
  ) {
    return ExpenseQuickSummary(
      todayExpenses: summary.todayExpenses,
      weeklyExpenses: summary.weeklyExpenses,
      monthlyExpenses: summary.monthlyExpenses,
      transactionCount: summary.transactionCount,
    );
  }
}

final expenseQuickSummaryProvider =
    StreamProvider.family<ExpenseQuickSummary, ExpenseSummaryScope>((
      ref,
      scope,
    ) {
      final firestore = ref.watch(firestoreProvider);
      final queue = ref.watch(offlineActionQueueProvider);
      final summaryStream = firestore
          .collection('project_summaries')
          .where('workspaceId', isEqualTo: scope.workspaceId)
          .where('projectId', isEqualTo: scope.projectId)
          .limit(1)
          .snapshots()
          .map((snap) {
            if (snap.docs.isEmpty) {
              return const ExpenseQuickSummary();
            }
            return ExpenseQuickSummary.fromProjectSummary(
              ProjectAccountingSummary.fromMap(snap.docs.first.data()),
            );
          });
      final pendingStream = queue.watch();

      return Stream.multi((controller) {
        var currentSummary = const ExpenseQuickSummary();
        var currentActions = const <OfflineAction>[];
        var hasSummary = false;
        var hasActions = false;

        void emit() {
          if (!hasSummary || !hasActions) {
            return;
          }
          controller.add(
            _mergePendingExpenseDeltas(currentSummary, currentActions, scope),
          );
        }

        final summarySub = summaryStream.listen((summary) {
          currentSummary = summary;
          hasSummary = true;
          emit();
        }, onError: controller.addError);
        final pendingSub = pendingStream.listen((actions) {
          currentActions = actions;
          hasActions = true;
          emit();
        }, onError: controller.addError);

        controller.onCancel = () async {
          await summarySub.cancel();
          await pendingSub.cancel();
        };
      });
    });

ExpenseQuickSummary _mergePendingExpenseDeltas(
  ExpenseQuickSummary summary,
  List<OfflineAction> actions,
  ExpenseSummaryScope scope,
) {
  var todayDelta = 0.0;
  var weeklyDelta = 0.0;
  var monthlyDelta = 0.0;
  var transactionDelta = 0;

  for (final action in actions) {
    if (action.type != OfflineActionTypes.createExpense ||
        action.status == OfflineActionStatus.synced ||
        action.status == OfflineActionStatus.deadLetter) {
      continue;
    }
    final payload = action.payload;
    if (payload['workspaceId'] != scope.workspaceId ||
        payload['projectId'] != scope.projectId) {
      continue;
    }
    final amount = (payload['amount'] as num?)?.toDouble() ?? 0;
    final date = DateTime.tryParse('${payload['date'] ?? ''}');
    if (date == null) {
      continue;
    }
    transactionDelta += 1;
    if (_isSameDay(date, scope.now)) {
      todayDelta += amount;
    }
    if (_isSameWeek(date, scope.now)) {
      weeklyDelta += amount;
    }
    if (_isSameMonth(date, scope.now)) {
      monthlyDelta += amount;
    }
  }

  return summary.copyWithPending(
    todayDelta: todayDelta,
    weeklyDelta: weeklyDelta,
    monthlyDelta: monthlyDelta,
    transactionDelta: transactionDelta,
  );
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameWeek(DateTime a, DateTime b) {
  final dayA = DateTime.utc(a.year, a.month, a.day);
  final dayB = DateTime.utc(b.year, b.month, b.day);
  final startB = dayB.subtract(Duration(days: dayB.weekday - 1));
  final endB = startB.add(const Duration(days: 6));
  return !dayA.isBefore(startB) && !dayA.isAfter(endB);
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}
