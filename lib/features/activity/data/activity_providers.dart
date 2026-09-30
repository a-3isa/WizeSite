import 'dart:async';
import 'package:buildtrack_app/core/sync/doc_source.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many of the most-recent expenses and payments the activity feed pulls
/// from each collection. The Activity tab is a "recent history" surface, not
/// an all-time ledger, so it stays bounded — this is deliberately NOT a
/// full-history scan (see the Cash Collected cost note in dashboard_providers).
const int _activityFeedLimit = 50;

/// Workspace-wide recent activity: the most recent expenses + payments merged
/// and sorted newest-first. Powers the Activity tab.
///
/// This replaces the tab's previous data source, which reused the dashboard's
/// rolling-7-day "weekly insights" stream (capped at 5 items) — that made the
/// Activity tab show "No data yet" whenever the latest transaction was older
/// than a week, even though the workspace had plenty of history.
final workspaceActivityProvider =
    StreamProvider.family<List<DashboardTransactionRef>, String>((
      ref,
      workspaceId,
    ) {
      final source = ref.watch(docSourceProvider);

      Stream<List<Doc>> recent(String collection) => source.watch(
        DocQuery(
          collection,
          equals: {'workspaceId': workspaceId, 'isArchived': false},
          orderBy: 'date',
          descending: true,
          limit: _activityFeedLimit,
        ),
      );

      final expensesStream = recent('expenses');
      final paymentsStream = recent('payments');

      return Stream.multi((controller) {
        List<DashboardTransactionRef>? expenses;
        List<DashboardTransactionRef>? payments;

        void emit() {
          if (expenses == null && payments == null) return;
          final items = <DashboardTransactionRef>[...?expenses, ...?payments]
            ..sort(
              (a, b) =>
                  (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
            );
          controller.add(
            items.take(_activityFeedLimit).toList(growable: false),
          );
        }

        final expenseSub = expensesStream.listen((docs) {
          expenses = docs
              .map((doc) {
                final e = Expense.fromMap(doc.id, doc.data);
                return DashboardTransactionRef(
                  id: e.id,
                  type: 'expense',
                  title: e.entityName.isNotEmpty
                      ? e.entityName
                      : (e.supplierName.isNotEmpty
                            ? e.supplierName
                            : e.description),
                  amount: e.amount,
                  date: e.date,
                );
              })
              .toList(growable: false);
          emit();
        }, onError: controller.addError);

        final paymentSub = paymentsStream.listen((docs) {
          payments = docs
              .map((doc) {
                final p = PaymentRecord.fromMap(doc.id, doc.data);
                return DashboardTransactionRef(
                  id: p.id,
                  type: 'payment',
                  title: p.entityName.isNotEmpty ? p.entityName : p.description,
                  amount: p.amount,
                  date: p.date,
                );
              })
              .toList(growable: false);
          emit();
        }, onError: controller.addError);

        controller.onCancel = () {
          unawaited(expenseSub.cancel());
          unawaited(paymentSub.cancel());
        };
      });
    });
