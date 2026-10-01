import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/pagination/record_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/contacts_service.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/add_worker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeContactsService extends ContactsService {
  const _FakeContactsService({
    required this.permissionStatus,
    required this.pickResult,
  });

  final ContactPermissionStatus permissionStatus;
  final PickedContactResult pickResult;

  @override
  Future<PickedContactResult> pickContact() async => pickResult;

  @override
  Future<ContactPermissionStatus> requestPermission() async => permissionStatus;
}

class _FakeWorkerRepository implements WorkerRepository {
  _FakeWorkerRepository({this.worker});

  final WorkerProfile? worker;
  WorkerStatus? createdStatus;
  WorkerStatus? updatedStatus;

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
  }) async {
    createdStatus = status;
  }

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
  }) async {
    updatedStatus = status;
  }

  @override
  Future<void> archiveWorker(String workerId) async {}

  @override
  Future<RecordPage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    Object? cursor,
    int pageSize = 20,
    Set<WorkerStatus>? statuses,
  }) async =>
      RecordPage(items: worker == null ? [] : [worker!], hasMore: false);

  @override
  Future<WorkerProfile?> getWorker(String workerId) async => worker;

  @override
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  }) => Stream.value(worker == null ? [] : [worker!]);
}

Widget _testApp(
  ContactsService contactsService, {
  WorkerRepository? workerRepository,
  String? workerId,
}) {
  final overrides = [
    activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
    activeUserIdProvider.overrideWith((ref) => 'user_1'),
    contactsServiceProvider.overrideWithValue(contactsService),
    if (workerRepository != null)
      workerRepositoryProvider.overrideWithValue(workerRepository),
  ];
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AddWorkerScreen(workerId: workerId),
    ),
  );
}

void main() {
  testWidgets('AddWorkerScreen imports name and phone from contacts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const _FakeContactsService(
          permissionStatus: ContactPermissionStatus.granted,
          pickResult: PickedContactResult.selected(
            PickedContact(name: 'Ali Hassan', phoneNumber: '+201005550101'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick from Contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Ali Hassan'), findsOneWidget);
    expect(find.text('+201005550101'), findsOneWidget);
  });

  testWidgets(
    'AddWorkerScreen keeps fields untouched when contacts permission is denied',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          const _FakeContactsService(
            permissionStatus: ContactPermissionStatus.denied,
            pickResult: PickedContactResult.cancelled(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Manual Worker');
      await tester.enterText(find.byType(TextField).at(1), '0100');
      await tester.tap(find.text('Pick from Contacts'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Worker'), findsOneWidget);
      expect(find.text('0100'), findsOneWidget);
    },
  );

  testWidgets(
    'AddWorkerScreen keeps fields untouched when selected contact has no phone',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          const _FakeContactsService(
            permissionStatus: ContactPermissionStatus.granted,
            pickResult: PickedContactResult.missingPhoneNumber(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Manual Worker');
      await tester.enterText(find.byType(TextField).at(1), '0100');
      await tester.tap(find.text('Pick from Contacts'));
      await tester.pumpAndSettle();

      expect(find.text('Manual Worker'), findsOneWidget);
      expect(find.text('0100'), findsOneWidget);
    },
  );

  testWidgets('AddWorkerScreen prefills and saves worker status on edit', (
    tester,
  ) async {
    final repository = _FakeWorkerRepository(
      worker: const WorkerProfile(
        id: 'w1',
        workspaceId: 'workspace_1',
        name: 'Sam Worker',
        phoneNumber: '0100',
        dailyWage: 100,
        billingType: 'daily',
        workerType: 'other',
        notes: '',
        isArchived: false,
        status: WorkerStatus.inactive,
      ),
    );

    await tester.pumpWidget(
      _testApp(
        const _FakeContactsService(
          permissionStatus: ContactPermissionStatus.denied,
          pickResult: PickedContactResult.cancelled(),
        ),
        workerRepository: repository,
        workerId: 'w1',
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);

    await tester.tap(find.text('Inactive').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminated').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Update Worker'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Update Worker'));
    await tester.pumpAndSettle();

    expect(repository.updatedStatus, WorkerStatus.terminated);
  });
}
