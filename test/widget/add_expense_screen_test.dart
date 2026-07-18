import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/accounting_categories.dart';
import 'package:buildtrack_app/core/constants/accounting_entity_types.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/add_expense_screen.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExpenseRepository implements ExpenseRepository {
  @override
  Future<MutationResult> archiveExpense(String expenseId) async {
    return const MutationResult();
  }

  @override
  Future<MutationResult> createExpense({
    required String workspaceId,
    required String userId,
    required String projectId,
    String? projectName,
    required String category,
    required double amount,
    String? currency,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    double? projectTotalExpensesBefore,
    List<Attachment>? attachments,
  }) async {
    return const MutationResult();
  }

  @override
  Future<FirestorePage<Expense>> fetchExpensesPage(
    String workspaceId, {
    required String projectId,
    String? entityId,
    String? entityName,
    String? entityType,
    String? category,
    String? paymentMethod,
    String? paymentStatus,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return const FirestorePage(items: [], hasMore: false);
  }

  @override
  Future<Expense?> getExpense(String expenseId) async => null;

  @override
  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required double amount,
    required DateTime date,
    String? notes,
    String? purpose,
    String? description,
    String? supplierName,
    String? entityId,
    String? entityName,
    String? entityType,
    String? paymentMethod,
    String? paymentStatus,
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<Expense>> watchExpenses(String workspaceId, String projectId) {
    return const Stream.empty();
  }
}

void main() {
  testWidgets(
    'AddExpenseScreen waits for category before showing detail fields',
    (tester) async {
      await tester.pumpWidget(_screen(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Purpose'), findsNothing);
      expect(find.text('Description'), findsNothing);
      expect(find.text('Payment method'), findsNothing);
      expect(find.text('Payment status'), findsNothing);
      expect(find.text('Currency'), findsNothing);
    },
  );

  testWidgets('AddExpenseScreen localizes attachment controls in Arabic', (
    tester,
  ) async {
    const locale = Locale('ar');
    final l10n = AppLocalizations(locale);
    await tester.pumpWidget(_screen(locale: locale));

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(l10n.expenseCategoryLabel(AccountingCategories.materials)).last,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('qa_add_expense_pick_attachments')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(l10n.t('attachments')), findsOneWidget);
    expect(find.text(l10n.t('selectAttachments')), findsOneWidget);
    expect(find.text('Attachments'), findsNothing);
    expect(find.text('Select attachments'), findsNothing);
  });

  testWidgets('resource category shows saved resources and calculates amount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final contractor = AppEntity(
      id: 'contractor_1',
      workspaceId: 'workspace_1',
      name: 'BuildCo',
      normalizedName: 'buildco',
      type: AccountingEntityTypes.contractor,
      createdAt: DateTime(2026),
      defaultRate: 250,
      rateUnit: 'day',
    );
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        entityRepository: _FakeEntityRepository([contractor]),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(
            AppLocalizations(
              const Locale('en'),
            ).expenseCategoryLabel(AccountingCategories.contractor),
          )
          .last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextField, 'Entity name (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('BuildCo'), findsOneWidget);

    await tester.tap(find.text('BuildCo'));
    await tester.pumpAndSettle();
    expect(find.text('250.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '3');
    await tester.pumpAndSettle();
    expect(find.text('750.00'), findsOneWidget);
  });

  testWidgets('worker category saves through worker entry repository', (
    tester,
  ) async {
    final worker = WorkerProfile(
      id: 'worker_1',
      workspaceId: 'workspace_1',
      name: 'Mina',
      phoneNumber: '0100',
      dailyWage: 120,
      billingType: 'daily',
      workerType: 'mason',
      notes: '',
      isArchived: false,
    );
    final entries = _FakeWorkerEntryRepository();
    await tester.pumpWidget(
      _screen(
        locale: const Locale('en'),
        projectId: 'project_1',
        workerRepository: _FakeWorkerRepository([worker]),
        workerEntryRepository: entries,
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa_add_expense_category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Worker').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownMenu<String>, 'Worker Name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mina').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Days Worked'), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    expect(entries.createdWorkerId, 'worker_1');
    expect(entries.createdProjectId, 'project_1');
    expect(entries.createdDaysWorked, 2);
    expect(entries.createdDailyWage, 120);
  });
}

Widget _screen({
  required Locale locale,
  EntityRepository? entityRepository,
  WorkerRepository? workerRepository,
  WorkerEntryRepository? workerEntryRepository,
  String? projectId,
}) {
  return ProviderScope(
    overrides: [
      activeWorkspaceIdProvider.overrideWith((ref) => 'workspace_1'),
      activeUserIdProvider.overrideWith((ref) => 'user_1'),
      expenseRepositoryProvider.overrideWithValue(_FakeExpenseRepository()),
      if (entityRepository != null)
        entityRepositoryProvider.overrideWithValue(entityRepository),
      if (workerRepository != null)
        workerRepositoryProvider.overrideWithValue(workerRepository),
      if (workerEntryRepository != null)
        workerEntryRepositoryProvider.overrideWithValue(workerEntryRepository),
      projectsProvider.overrideWith((ref) => Stream.value(const [])),
      currentUserSettingsProvider.overrideWith(
        (ref) => Stream.value(
          UserSettings.defaults(userId: 'user_1', email: 'user@test.com'),
        ),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AddExpenseScreen(projectId: projectId),
    ),
  );
}

class _FakeEntityRepository implements EntityRepository {
  const _FakeEntityRepository(this.entities);

  final List<AppEntity> entities;

  @override
  Future<AppEntity> createEntity({
    required String workspaceId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    return entities.first;
  }

  @override
  Future<void> deleteEntity(String entityId) async {}

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async {
    return entities.firstWhere((entity) => entity.name == name);
  }

  @override
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return FirestorePage(
      items: entities.where((entity) => entity.type == type).toList(),
      hasMore: false,
    );
  }

  @override
  Future<AppEntity?> getEntityById(String entityId) async {
    return entities.firstWhere((entity) => entity.id == entityId);
  }

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async {
    return entities.firstWhere((entity) => entity.name == name);
  }

  @override
  Future<void> saveAttachments({
    required String entityId,
    required List<Map<String, dynamic>> attachments,
  }) async {}

  @override
  Future<List<AppEntity>> searchEntities(
    String workspaceId,
    String query, {
    String? type,
    int limit = 20,
  }) async {
    return entities
        .where((entity) => entity.workspaceId == workspaceId)
        .where((entity) => type == null || entity.type == type)
        .where((entity) => entity.normalizedName.contains(query.toLowerCase()))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<AppEntity> updateEntity({
    required String entityId,
    required String name,
    required String type,
    double? defaultRate,
    String? rateUnit,
    String? phoneNumber,
    String? notes,
  }) async {
    return entities.first;
  }

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) {
    return Stream.value(entities);
  }
}

class _FakeWorkerRepository implements WorkerRepository {
  const _FakeWorkerRepository(this.workers);

  final List<WorkerProfile> workers;

  @override
  Future<void> archiveWorker(String workerId) async {}

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
  Future<FirestorePage<WorkerProfile>> fetchWorkersPage(
    String workspaceId, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
    Set<WorkerStatus>? statuses,
  }) async {
    return FirestorePage(items: workers, hasMore: false);
  }

  @override
  Future<WorkerProfile?> getWorker(String workerId) async {
    return workers.firstWhere((worker) => worker.id == workerId);
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
  }) async {}

  @override
  Stream<List<WorkerProfile>> watchWorkers(
    String workspaceId, {
    Set<WorkerStatus>? statuses,
  }) {
    return Stream.value(workers);
  }
}

class _FakeWorkerEntryRepository implements WorkerEntryRepository {
  String? createdWorkerId;
  String? createdProjectId;
  double? createdDaysWorked;
  double? createdDailyWage;

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
    List<Attachment>? attachments,
    double? projectTotalExpensesBefore,
  }) async {
    createdWorkerId = workerId;
    createdProjectId = projectId;
    createdDaysWorked = daysWorked;
    createdDailyWage = dailyWage;
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
    List<Attachment>? attachments,
  }) async {}

  @override
  Stream<List<WorkerEntryRecord>> watchEntriesByWorker({
    required String workspaceId,
    required String workerId,
  }) {
    return const Stream.empty();
  }
}
