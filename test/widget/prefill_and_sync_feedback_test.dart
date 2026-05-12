import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/add_expense_screen.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockExpenseRepository extends Mock implements ExpenseRepository {}

class _NoopOfflineQueueCoordinator extends OfflineQueueCoordinator {
  _NoopOfflineQueueCoordinator(super.ref);

  @override
  Future<void> refreshCounts() async {}

  @override
  Future<void> drainNow() async {}
}

void main() {
  testWidgets('AddExpenseScreen shows a recoverable error when prefill fails', (
    tester,
  ) async {
    final repository = _MockExpenseRepository();
    when(() => repository.getExpense(any())).thenThrow(Exception('boom'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(repository),
          projectsProvider.overrideWith(
            (ref) => Stream.value(const <Project>[]),
          ),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(
              UserSettings.defaults(userId: 'user_1', email: 'user@test.com'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AddExpenseScreen(expenseId: 'expense_1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('AppBootstrapScope surfaces dead-letter sync failures to users', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlineQueueCoordinatorProvider.overrideWith(
            (ref) => _NoopOfflineQueueCoordinator(ref),
          ),
          connectivityProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: const MaterialApp(
          home: AppBootstrapScope(child: Scaffold(body: Text('bootstrap'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('bootstrap')),
      listen: false,
    );

    container
        .read(offlineSyncNoticeProvider.notifier)
        .state = const OfflineSyncNotice(
      actionId: 'dead_1',
      type: OfflineSyncFailureType.generic,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('A queued action failed to sync.'), findsOneWidget);
  });
}
