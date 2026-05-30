import 'dart:io';

import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('expense_repository_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_actions_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('offline_actions_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fetchExpensesPage filters by entityId', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('expenses').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityId': 'entity_1',
      'entityName': 'Client A',
      'amount': 35,
      'date': DateTime.utc(2026, 5, 25),
    });
    await firestore.collection('expenses').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityId': 'entity_2',
      'entityName': 'Client B',
      'amount': 45,
      'date': DateTime.utc(2026, 5, 26),
    });

    final mutationService = _MockWorkspaceMutationService();
    final repository = FirebaseExpenseRepository(
      firestore,
      mutationService,
      queue,
    );

    final page = await repository.fetchExpensesPage(
      'workspace_1',
      projectId: 'project_1',
      entityId: 'entity_1',
      cursor: null,
      pageSize: 20,
    );

    expect(page.items, hasLength(1));
    expect(page.items.first.entityId, 'entity_1');
    expect(page.hasMore, isFalse);
  });

  test(
    'fetchExpensesPage filters old records by entityName fallback',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('expenses').add({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'isArchived': false,
        'supplierName': 'Steel Supplier',
        'amount': 35,
        'date': DateTime.utc(2026, 5, 25),
      });
      await firestore.collection('expenses').add({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'isArchived': false,
        'supplierName': 'Concrete Supplier',
        'amount': 45,
        'date': DateTime.utc(2026, 5, 26),
      });

      final repository = FirebaseExpenseRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchExpensesPage(
        'workspace_1',
        projectId: 'project_1',
        entityName: 'Steel Supplier',
        cursor: null,
        pageSize: 20,
      );

      expect(page.items, hasLength(1));
      expect(page.items.first.supplierName, 'Steel Supplier');
    },
  );

  test(
    'fetchExpensesPage combines category, payment status, and entity type',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('expenses').add({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'isArchived': false,
        'category': 'materials',
        'paymentStatus': 'unpaid',
        'entityType': 'supplier',
        'amount': 35,
        'date': DateTime.utc(2026, 5, 25),
      });
      await firestore.collection('expenses').add({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'isArchived': false,
        'category': 'materials',
        'paymentStatus': 'paid',
        'entityType': 'supplier',
        'amount': 45,
        'date': DateTime.utc(2026, 5, 26),
      });
      await firestore.collection('expenses').add({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'isArchived': false,
        'category': 'materials',
        'paymentStatus': 'unpaid',
        'entityType': 'worker',
        'amount': 55,
        'date': DateTime.utc(2026, 5, 27),
      });

      final repository = FirebaseExpenseRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchExpensesPage(
        'workspace_1',
        projectId: 'project_1',
        category: 'materials',
        paymentStatus: 'unpaid',
        entityType: 'supplier',
        cursor: null,
        pageSize: 20,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.amount, 35);
      expect(page.items.single.paymentStatus, 'unpaid');
      expect(page.items.single.entityType, 'supplier');
    },
  );

  test('fetchExpensesPage searches entity, description, and notes', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('expenses').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Steel Supplier',
      'supplierName': 'Steel Supplier',
      'description': 'Rebar invoice',
      'notes': 'north wing',
      'amount': 35,
      'date': DateTime.utc(2026, 5, 25),
    });
    await firestore.collection('expenses').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Paint Crew',
      'supplierName': 'Paint Crew',
      'description': 'Paint',
      'notes': 'south wing',
      'amount': 45,
      'date': DateTime.utc(2026, 5, 26),
    });

    final repository = FirebaseExpenseRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final entityMatch = await repository.fetchExpensesPage(
      'workspace_1',
      projectId: 'project_1',
      searchText: 'steel',
      cursor: null,
      pageSize: 20,
    );
    final noteMatch = await repository.fetchExpensesPage(
      'workspace_1',
      projectId: 'project_1',
      searchText: 'south',
      cursor: null,
      pageSize: 20,
    );
    final descriptionMatch = await repository.fetchExpensesPage(
      'workspace_1',
      projectId: 'project_1',
      searchText: 'rebar',
      cursor: null,
      pageSize: 20,
    );

    expect(entityMatch.items.single.entityName, 'Steel Supplier');
    expect(noteMatch.items.single.entityName, 'Paint Crew');
    expect(descriptionMatch.items.single.description, 'Rebar invoice');
  });

  test(
    'fetchExpensesPage keeps pending creates that match active filters',
    () async {
      final firestore = FakeFirebaseFirestore();
      await queue.enqueue(
        type: OfflineActionTypes.createExpense,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'category': 'materials',
          'entityId': 'entity_1',
          'entityName': 'Steel Supplier',
          'amount': 35,
          'date': DateTime.utc(2026, 5, 25).toIso8601String(),
          'paymentMethod': 'cash',
        },
      );
      await queue.enqueue(
        type: OfflineActionTypes.createExpense,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'category': 'labor',
          'entityId': 'entity_2',
          'entityName': 'Labor Crew',
          'amount': 45,
          'date': DateTime.utc(2026, 5, 26).toIso8601String(),
          'paymentMethod': 'cash',
        },
      );

      final repository = FirebaseExpenseRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchExpensesPage(
        'workspace_1',
        projectId: 'project_1',
        entityId: 'entity_1',
        category: 'materials',
        cursor: null,
        pageSize: 20,
      );

      expect(page.items, hasLength(1));
      expect(page.items.first.entityId, 'entity_1');
      expect(page.items.first.category, 'materials');
    },
  );

  test('createExpense forwards structured accounting fields', () async {
    final firestore = FakeFirebaseFirestore();
    final mutationService = _MockWorkspaceMutationService();
    when(
      () => mutationService.createManualExpense(
        workspaceId: any(named: 'workspaceId'),
        projectId: any(named: 'projectId'),
        projectName: any(named: 'projectName'),
        category: any(named: 'category'),
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
        date: any(named: 'date'),
        notes: any(named: 'notes'),
        purpose: any(named: 'purpose'),
        description: any(named: 'description'),
        supplierName: any(named: 'supplierName'),
        entityId: any(named: 'entityId'),
        entityName: any(named: 'entityName'),
        entityType: any(named: 'entityType'),
        paymentMethod: any(named: 'paymentMethod'),
        paymentStatus: any(named: 'paymentStatus'),
        projectTotalExpensesBefore: any(named: 'projectTotalExpensesBefore'),
      ),
    ).thenAnswer((_) async => const MutationResult(queued: true));

    final repository = FirebaseExpenseRepository(
      firestore,
      mutationService,
      queue,
    );

    await repository.createExpense(
      workspaceId: 'workspace_1',
      userId: 'user_1',
      projectId: 'project_1',
      projectName: 'Tower',
      category: 'materials',
      amount: 1200,
      date: DateTime.utc(2026, 5, 27),
      purpose: 'Concrete delivery',
      description: 'Morning delivery',
      notes: 'Gate 2',
      supplierName: 'Acme Materials',
      entityId: 'entity_1',
      entityName: 'Acme Materials',
      entityType: 'supplier',
      paymentMethod: 'cash',
      paymentStatus: PaymentStatuses.partial,
    );

    verify(
      () => mutationService.createManualExpense(
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        projectName: 'Tower',
        category: 'materials',
        amount: 1200,
        currency: 'EGP',
        date: DateTime.utc(2026, 5, 27),
        purpose: 'Concrete delivery',
        description: 'Morning delivery',
        notes: 'Gate 2',
        supplierName: 'Acme Materials',
        entityId: 'entity_1',
        entityName: 'Acme Materials',
        entityType: 'supplier',
        paymentMethod: 'cash',
        paymentStatus: PaymentStatuses.partial,
        projectTotalExpensesBefore: null,
      ),
    ).called(1);
  });
}
