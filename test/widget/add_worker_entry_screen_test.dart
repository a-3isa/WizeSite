import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_entry_screen.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWorkerEntryRepository implements WorkerEntryRepository {
  String? createdWorkerId;

  @override
  Future<MutationResult> archiveEntry(String entryId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createEntry({
    required String workspaceId,
    required String userId,
    required String workerId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  }) async {
    createdWorkerId = workerId;
    return const MutationResult();
  }

  @override
  Future<WorkerEntryRecord?> getEntry(String entryId) async => null;

  @override
  Future<void> updateEntry({
    required String entryId,
    required String projectId,
    required double daysWorked,
    required double dailyWage,
    required DateTime date,
    String? notes,
  }) async {}

  @override
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return const Stream.empty();
  }
}

WorkerProfile _worker(String id, String name) {
  return WorkerProfile(
    id: id,
    workspaceId: 'workspace_1',
    name: name,
    phoneNumber: '0100',
    dailyWage: 120,
    billingType: 'daily',
    workerType: 'laborer',
    notes: '',
    isArchived: false,
  );
}

Project _project() {
  return const Project(
    id: 'project_1',
    workspaceId: 'workspace_1',
    name: 'Tower A',
    clientName: 'Client',
    contractValue: 1000,
    status: 'active',
    completionPercentage: 0,
    totalExpenses: 0,
    totalPayments: 0,
    netProfit: 0,
    isArchived: false,
  );
}

void main() {
  testWidgets(
    'AddWorkerEntryScreen clears an invalid selected worker and lets the user pick a valid one',
    (tester) async {
      final entryRepository = _FakeWorkerEntryRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
            activeUserIdProvider.overrideWith((ref) => 'user_1'),
            workersProvider.overrideWith(
              (ref) => Stream.value([
                _worker('worker_1', 'Worker One'),
                _worker('worker_2', 'Worker Two'),
              ]),
            ),
            projectsProvider.overrideWith((ref) => Stream.value([_project()])),
            workerEntryRepositoryProvider.overrideWithValue(entryRepository),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: AddWorkerEntryScreen(
              workerId: 'worker_missing',
              projectId: 'project_1',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Worker One').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.tap(find.text('Save Worker Entry'));
      await tester.pumpAndSettle();

      expect(entryRepository.createdWorkerId, 'worker_1');
    },
  );
}
