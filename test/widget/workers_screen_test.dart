import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WorkersScreen shows status badges and filters by status', (
    tester,
  ) async {
    final repository = _FakeWorkerRepository([
      _worker('w1', 'Active Annie', WorkerStatus.active),
      _worker('w2', 'Idle Omar', WorkerStatus.inactive),
      _worker('w3', 'Terminated Tim', WorkerStatus.terminated),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
          workerRepositoryProvider.overrideWithValue(repository),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(
              UserSettings.defaults(userId: 'user_1', email: 'u@example.com'),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: WorkersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Active'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Inactive'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Terminated'), findsOneWidget);
    expect(find.byKey(const Key('qa_worker_add')), findsOneWidget);
    expect(find.byKey(const Key('qa_worker_actions_w1')), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Inactive'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Terminated'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa_worker_actions_w1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Inactive'));
    await tester.pumpAndSettle();

    expect(find.text('Idle Omar'), findsOneWidget);
    expect(find.text('Active Annie'), findsNothing);
    expect(find.text('Terminated Tim'), findsNothing);
  });
}

WorkerProfile _worker(String id, String name, WorkerStatus status) =>
    WorkerProfile(
      id: id,
      workspaceId: 'workspace_1',
      name: name,
      phoneNumber: '0100',
      dailyWage: 100,
      billingType: 'daily',
      workerType: 'other',
      notes: '',
      isArchived: false,
      status: status,
    );

class _FakeWorkerRepository implements WorkerRepository {
  const _FakeWorkerRepository(this.workers);

  final List<WorkerProfile> workers;

  @override
  Future<void> createWorker({
    required String workspaceId,
    required String userId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus status = WorkerStatus.active,
  }) async {}

  @override
  Future<void> updateWorker({
    required String workerId,
    required String name,
    required String phoneNumber,
    required double dailyWage,
    required String billingType,
    String? workerType,
    String? notes,
    WorkerStatus? status,
  }) async {}

  @override
  Future<void> archiveWorker(String workerId) async {}

  @override
  Future<FirestorePage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
    Set<WorkerStatus>? statuses,
  }) async => FirestorePage(
    items: workers
        .where((worker) => statuses == null || statuses.contains(worker.status))
        .toList(growable: false),
    hasMore: false,
  );

  @override
  Future<WorkerProfile?> getWorker(String workerId) async {
    for (final worker in workers) {
      if (worker.id == workerId) return worker;
    }
    return null;
  }

  @override
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  }) => Stream.value(
    workers
        .where((worker) => statuses == null || statuses.contains(worker.status))
        .toList(growable: false),
  );
}
