import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/pagination/firestore_page.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:buildtrack_app/features/entities/presentation/screens/entity_detail_screen.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/screens/expense_detail_screen.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/payments/presentation/screens/payment_detail_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/domain/user_settings.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:buildtrack_app/features/workers/presentation/screens/worker_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageUploadService extends Mock implements StorageUploadService {}

void main() {
  testWidgets('expense detail shows a loading skeleton while loading', (
    tester,
  ) async {
    final expense = Completer<Expense?>();

    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          storageUploadServiceProvider.overrideWithValue(
            _MockStorageUploadService(),
          ),
          expenseDetailsProvider.overrideWith(
            (ref, expenseId) => expense.future,
          ),
        ],
        child: const ExpenseDetailScreen(expenseId: 'expense_1'),
      ),
    );

    await tester.pump();

    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
  });

  testWidgets('expense detail shows a sanitized provider error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          storageUploadServiceProvider.overrideWithValue(
            _MockStorageUploadService(),
          ),
          expenseDetailsProvider.overrideWith(
            (ref, expenseId) => Future.error(StateError('raw expense secret')),
          ),
        ],
        child: const ExpenseDetailScreen(expenseId: 'expense_1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw expense secret'), findsNothing);
  });

  testWidgets('expense detail renders the selected expense fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          storageUploadServiceProvider.overrideWithValue(
            _MockStorageUploadService(),
          ),
          expenseRepositoryProvider.overrideWithValue(
            _FakeExpenseRepository(
              Expense(
                id: 'expense_1',
                workspaceId: 'workspace_1',
                projectId: 'project_1',
                projectName: 'Villa Build',
                category: 'materials',
                amount: 1250,
                currency: 'USD',
                date: DateTime.utc(2026, 6, 17),
                notes: 'Urgent delivery',
                purpose: 'Concrete materials',
                description: 'Concrete materials',
                supplierName: 'Steel Supplier',
                paymentMethod: 'cash',
                paymentStatus: 'paid',
                inputMethod: 'manual',
                transcript: '',
                source: '',
                storagePath: '',
                isArchived: false,
                attachments: const [],
              ),
            ),
          ),
        ],
        child: const ExpenseDetailScreen(expenseId: 'expense_1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('USD'), findsWidgets);
    expect(find.textContaining('Villa Build'), findsOneWidget);
    expect(find.textContaining('Steel Supplier'), findsOneWidget);
    expect(find.textContaining('Urgent delivery'), findsOneWidget);
  });

  testWidgets('expense detail renders inline previews for image attachments', (
    tester,
  ) async {
    final expense = Expense(
      id: 'expense_1',
      workspaceId: 'workspace_1',
      projectId: 'project_1',
      projectName: 'Villa Build',
      category: 'materials',
      amount: 1250,
      currency: 'USD',
      date: DateTime.utc(2026, 6, 17),
      notes: '',
      supplierName: 'Steel Supplier',
      paymentMethod: 'cash',
      paymentStatus: 'paid',
      inputMethod: 'manual',
      transcript: '',
      source: '',
      storagePath: '',
      isArchived: false,
      attachments: [
        Attachment(
          id: 'image_1',
          fileName: 'receipt.png',
          storagePath: 'attachments/receipt.png',
          contentType: 'image/png',
          downloadUrl: 'https://example.com/receipt.png',
          uploadedAt: DateTime.utc(2026, 6, 17),
        ),
      ],
    );

    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          storageUploadServiceProvider.overrideWithValue(
            _MockStorageUploadService(),
          ),
          expenseRepositoryProvider.overrideWithValue(
            _FakeExpenseRepository(expense),
          ),
        ],
        child: const ExpenseDetailScreen(expenseId: 'expense_1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('qa_expense_image_preview_image_1')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('worker detail shows a sanitized provider error', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          workerDetailsProvider.overrideWith(
            (ref, workerId) => Future.error(StateError('raw worker secret')),
          ),
          workerEntriesProvider.overrideWith(
            (ref, workerId) => const Stream.empty(),
          ),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
          ),
        ],
        child: const WorkerDetailScreen(workerId: 'worker_1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw worker secret'), findsNothing);
  });

  testWidgets('payment detail shows a loading skeleton while loading', (
    tester,
  ) async {
    final payment = Completer<PaymentRecord?>();

    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          paymentDetailsProvider.overrideWith(
            (ref, paymentId) => payment.future,
          ),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
          ),
        ],
        child: const PaymentDetailScreen(paymentId: 'payment_1'),
      ),
    );

    await tester.pump();

    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
  });

  testWidgets('worker detail shows a loading skeleton while worker loads', (
    tester,
  ) async {
    final worker = Completer<WorkerProfile?>();

    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          workerDetailsProvider.overrideWith((ref, workerId) => worker.future),
          workerEntriesProvider.overrideWith(
            (ref, workerId) => const Stream.empty(),
          ),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
          ),
        ],
        child: const WorkerDetailScreen(workerId: 'worker_1'),
      ),
    );

    await tester.pump();

    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
  });

  testWidgets('worker detail shows a loading skeleton while entries load', (
    tester,
  ) async {
    final entries = StreamController<List<WorkerEntryRecord>>();
    addTearDown(entries.close);

    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          workerDetailsProvider.overrideWith(
            (ref, workerId) async => const WorkerProfile(
              id: 'worker_1',
              workspaceId: 'workspace_1',
              name: 'Sam Worker',
              phoneNumber: '0100',
              dailyWage: 250,
              billingType: 'daily',
              workerType: 'mason',
              notes: '',
              isArchived: false,
            ),
          ),
          workerEntriesProvider.overrideWith((ref, workerId) => entries.stream),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(UserSettings.defaults(userId: 'user_1')),
          ),
        ],
        child: const WorkerDetailScreen(workerId: 'worker_1'),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(AppLoadingSkeleton), findsOneWidget);
  });

  testWidgets('worker detail renders the selected worker and recent entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          workerDetailsProvider.overrideWith(
            (ref, workerId) async => const WorkerProfile(
              id: 'worker_1',
              workspaceId: 'workspace_1',
              name: 'Sam Worker',
              phoneNumber: '0100',
              dailyWage: 250,
              billingType: 'daily',
              workerType: 'mason',
              notes: '',
              isArchived: false,
            ),
          ),
          workerEntriesProvider.overrideWith(
            (ref, workerId) => Stream.value([
              WorkerEntryRecord(
                id: 'entry_1',
                workspaceId: 'workspace_1',
                workerId: 'worker_1',
                projectId: 'project_1',
                daysWorked: 2,
                dailyWage: 250,
                totalCost: 500,
                date: DateTime.utc(2026, 6, 17),
                notes: 'Foundation work',
                isArchived: false,
              ),
            ]),
          ),
          currentUserSettingsProvider.overrideWith(
            (ref) => Stream.value(
              UserSettings.defaults(
                userId: 'user_1',
              ).copyWith(defaultCurrency: 'USD'),
            ),
          ),
        ],
        child: const WorkerDetailScreen(workerId: 'worker_1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Sam Worker'), findsOneWidget);
    expect(find.textContaining('0100'), findsOneWidget);
    expect(find.textContaining('USD'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('entity detail renders the selected entity and attachments', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        overrides: [
          entityRepositoryProvider.overrideWithValue(
            _FakeEntityRepository(
              entity: AppEntity(
                id: 'entity_1',
                workspaceId: 'workspace_1',
                name: 'Steel Supplier',
                normalizedName: 'steel supplier',
                type: 'supplier',
                createdAt: DateTime.utc(2026, 6, 17),
                attachments: const [],
              ),
            ),
          ),
        ],
        child: const EntityDetailScreen(entityId: 'entity_1'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Steel Supplier'), findsOneWidget);
    expect(find.text('supplier'), findsOneWidget);
    expect(find.text('No data yet'), findsOneWidget);
  });
}

Widget _localizedApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
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
      home: child,
    ),
  );
}

class _FakeEntityRepository implements EntityRepository {
  const _FakeEntityRepository({required this.entity});

  final AppEntity entity;

  @override
  Future<FirestorePage<AppEntity>> fetchEntityDirectoryPage(
    String workspaceId, {
    required String type,
    EntityDirectorySort sort = EntityDirectorySort.recent,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int pageSize = 20,
  }) async {
    return FirestorePage(items: [entity], hasMore: false);
  }

  @override
  Future<AppEntity?> getEntityById(String entityId) async => entity;

  @override
  Future<AppEntity?> getEntityByName(
    String workspaceId,
    String name, {
    String? type,
  }) async {
    return entity.name == name ? entity : null;
  }

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
    return entity;
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
    return entity;
  }

  @override
  Future<void> deleteEntity(String entityId) async {}

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
    return [entity];
  }

  @override
  Stream<List<AppEntity>> watchEntities(
    String workspaceId, {
    String? type,
    int limit = 20,
  }) {
    return Stream.value([entity]);
  }

  @override
  Future<AppEntity?> ensureEntity({
    required String workspaceId,
    required String name,
    String? type,
  }) async {
    return entity;
  }
}

class _FakeExpenseRepository implements ExpenseRepository {
  const _FakeExpenseRepository(this.expense);

  final Expense expense;

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
    return FirestorePage(items: [expense], hasMore: false);
  }

  @override
  Future<Expense?> getExpense(String expenseId) async => expense;

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
    return Stream.value([expense]);
  }
}
