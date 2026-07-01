import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/features/settings/presentation/screens/sync_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<OfflineAction> actions,
    Future<void> Function(String actionId)? onRetryAction,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SyncStatusScreen(
            actions: actions,
            onRetryAction: onRetryAction,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'SyncStatusScreen lists pending, failed, dead-letter, and resolved items',
    (tester) async {
      final now = DateTime.now();
      final pending = _action(
        id: 'pending_1',
        type: 'create_expense',
        payload: {'expenseId': 'expense_1'},
        createdAt: now,
      );
      final failed = _action(
        id: 'failed_1',
        type: 'update_payment',
        payload: {'paymentId': 'payment_1'},
        status: OfflineActionStatus.failed,
        createdAt: now,
        lastError: 'Network unavailable',
        lastErrorCode: 'unavailable',
        nextAttemptAt: now.add(const Duration(minutes: 1)),
      );
      final dead = _action(
        id: 'dead_1',
        type: 'archive_worker',
        payload: {'workerId': 'worker_1'},
        status: OfflineActionStatus.deadLetter,
        createdAt: now,
        lastError: 'Permission denied',
        lastErrorCode: 'permission-denied',
      );
      final resolved = _action(
        id: 'resolved_1',
        type: 'update_expense',
        payload: {'expenseId': 'expense_2'},
        status: OfflineActionStatus.synced,
        createdAt: now,
        syncedAt: now,
        resolutionType: OfflineActionResolutionType.skippedNewerVersion,
        resolutionAt: now,
        resolutionTargetId: 'expense_2',
      );

      await pumpScreen(tester, actions: [pending, failed, dead, resolved]);

      expect(find.text('Sync status'), findsOneWidget);
      expect(find.text('Pending sync'), findsOneWidget);
      expect(find.text('Sync failed'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Recently resolved'), findsOneWidget);
      expect(find.text('create expense'), findsOneWidget);
      expect(find.text('update payment'), findsOneWidget);
      expect(find.text('archive worker'), findsOneWidget);
      expect(
        find.text(
          'A newer version was kept. Your older change was not applied.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Network unavailable'), findsOneWidget);
      expect(
        find.textContaining(pending.createdAt.year.toString()),
        findsWidgets,
      );
    },
  );

  testWidgets('SyncStatusScreen retries one failed item', (tester) async {
    final now = DateTime.now();
    final failed = _action(
      id: 'failed_1',
      type: 'update_payment',
      payload: {'paymentId': 'payment_1'},
      status: OfflineActionStatus.failed,
      createdAt: now,
      retryCount: 2,
      lastError: 'Network unavailable',
      lastErrorCode: 'unavailable',
      nextAttemptAt: now.add(const Duration(minutes: 1)),
    );
    final other = _action(
      id: 'failed_2',
      type: 'update_expense',
      payload: {'expenseId': 'expense_1'},
      status: OfflineActionStatus.failed,
      createdAt: now,
      retryCount: 1,
      lastError: 'Permission denied',
      lastErrorCode: 'permission-denied',
      nextAttemptAt: now.add(const Duration(minutes: 1)),
    );
    final retriedIds = <String>[];

    await pumpScreen(
      tester,
      actions: [failed, other],
      onRetryAction: (actionId) async => retriedIds.add(actionId),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Retry sync').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(retriedIds, ['failed_1']);
  });
}

OfflineAction _action({
  required String id,
  required String type,
  required Map<String, dynamic> payload,
  required DateTime createdAt,
  String status = OfflineActionStatus.pending,
  int retryCount = 0,
  String? lastError,
  String? lastErrorCode,
  DateTime? nextAttemptAt,
  DateTime? syncedAt,
  String? resolutionType,
  DateTime? resolutionAt,
  String? resolutionTargetId,
}) {
  return OfflineAction(
    id: id,
    type: type,
    payload: payload,
    createdAt: createdAt,
    status: status,
    retryCount: retryCount,
    lastError: lastError,
    lastErrorCode: lastErrorCode,
    nextAttemptAt: nextAttemptAt,
    syncedAt: syncedAt,
    resolutionType: resolutionType,
    resolutionAt: resolutionAt,
    resolutionTargetId: resolutionTargetId,
  );
}
