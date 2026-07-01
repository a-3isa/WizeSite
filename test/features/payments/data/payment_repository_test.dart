import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/core/constants/payment_statuses.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'dart:io';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('payment_repository_test_');
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

  test('createPayment uses project metrics as the baseline source', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('projects').doc('project_1').set({
      'workspaceId': 'workspace_1',
      'totalPayments': 999,
    });
    await firestore.collection('project_metrics').doc('project_1').set({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'totalPayments': 200,
    });
    final mutationService = _MockWorkspaceMutationService();
    when(
      () => mutationService.createPayment(
        workspaceId: any(named: 'workspaceId'),
        projectId: any(named: 'projectId'),
        amount: any(named: 'amount'),
        date: any(named: 'date'),
        paymentMethod: any(named: 'paymentMethod'),
        notes: any(named: 'notes'),
        projectTotalPaymentsBefore: any(named: 'projectTotalPaymentsBefore'),
      ),
    ).thenAnswer((_) async => const MutationResult(queued: true));

    final repository = FirebasePaymentRepository(
      firestore,
      mutationService,
      queue,
    );

    await repository.createPayment(
      workspaceId: 'workspace_1',
      userId: 'user_1',
      projectId: 'project_1',
      amount: 100,
      date: DateTime.utc(2026, 5, 20),
      paymentMethod: 'cash',
    );

    final captured = verify(
      () => mutationService.createPayment(
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        amount: 100,
        date: DateTime.utc(2026, 5, 20),
        paymentMethod: 'cash',
        notes: any(named: 'notes'),
        projectTotalPaymentsBefore: captureAny(
          named: 'projectTotalPaymentsBefore',
        ),
      ),
    ).captured;
    expect(captured.single, 200);
  });

  test('fetchPaymentsPage filters by entityId', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityId': 'entity_1',
      'entityName': 'Client A',
      'amount': 100,
      'date': DateTime.utc(2026, 5, 20),
      'paymentMethod': 'cash',
    });
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityId': 'entity_2',
      'entityName': 'Client B',
      'amount': 120,
      'date': DateTime.utc(2026, 5, 21),
      'paymentMethod': 'bank',
    });

    final mutationService = _MockWorkspaceMutationService();
    final repository = FirebasePaymentRepository(
      firestore,
      mutationService,
      queue,
    );

    final page = await repository.fetchPaymentsPage(
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

  test('fetchPaymentsPage filters by entityName fallback', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client A',
      'amount': 100,
      'date': DateTime.utc(2026, 5, 20),
      'paymentMethod': 'cash',
    });
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client B',
      'amount': 120,
      'date': DateTime.utc(2026, 5, 21),
      'paymentMethod': 'bank',
    });

    final repository = FirebasePaymentRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final page = await repository.fetchPaymentsPage(
      'workspace_1',
      projectId: 'project_1',
      entityName: 'Client A',
      cursor: null,
      pageSize: 20,
    );

    expect(page.items, hasLength(1));
    expect(page.items.first.entityName, 'Client A');
  });

  test('fetchPaymentsPage combines payment status and entity type', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client A',
      'entityType': 'supplier',
      'paymentStatus': 'paid',
      'paymentMethod': 'cash',
      'amount': 35,
      'date': DateTime.utc(2026, 5, 25),
    });
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client B',
      'entityType': 'supplier',
      'paymentStatus': 'unpaid',
      'paymentMethod': 'cash',
      'amount': 45,
      'date': DateTime.utc(2026, 5, 26),
    });
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client C',
      'entityType': 'worker',
      'paymentStatus': 'paid',
      'paymentMethod': 'cash',
      'amount': 55,
      'date': DateTime.utc(2026, 5, 27),
    });

    final repository = FirebasePaymentRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final page = await repository.fetchPaymentsPage(
      'workspace_1',
      projectId: 'project_1',
      paymentStatus: 'paid',
      entityType: 'supplier',
      cursor: null,
      pageSize: 20,
    );

    expect(page.items, hasLength(1));
    expect(page.items.single.amount, 35);
    expect(page.items.single.paymentStatus, 'paid');
    expect(page.items.single.entityType, 'supplier');
  });

  test('fetchPaymentsPage searches entity, description, and notes', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client A',
      'description': 'Deposit transfer',
      'notes': 'phase one',
      'paymentMethod': 'cash',
      'amount': 35,
      'date': DateTime.utc(2026, 5, 25),
    });
    await firestore.collection('payments').add({
      'workspaceId': 'workspace_1',
      'projectId': 'project_1',
      'isArchived': false,
      'entityName': 'Client B',
      'description': 'Retention release',
      'notes': 'final handover',
      'paymentMethod': 'bank',
      'amount': 45,
      'date': DateTime.utc(2026, 5, 26),
    });

    final repository = FirebasePaymentRepository(
      firestore,
      _MockWorkspaceMutationService(),
      queue,
    );

    final entityMatch = await repository.fetchPaymentsPage(
      'workspace_1',
      projectId: 'project_1',
      searchText: 'client a',
      cursor: null,
      pageSize: 20,
    );
    final noteMatch = await repository.fetchPaymentsPage(
      'workspace_1',
      projectId: 'project_1',
      searchText: 'handover',
      cursor: null,
      pageSize: 20,
    );
    final descriptionMatch = await repository.fetchPaymentsPage(
      'workspace_1',
      projectId: 'project_1',
      searchText: 'deposit',
      cursor: null,
      pageSize: 20,
    );

    expect(entityMatch.items.single.entityName, 'Client A');
    expect(noteMatch.items.single.entityName, 'Client B');
    expect(descriptionMatch.items.single.description, 'Deposit transfer');
  });

  test(
    'fetchPaymentsPage keeps pending creates that match active filters',
    () async {
      final firestore = FakeFirebaseFirestore();
      await queue.enqueue(
        type: OfflineActionTypes.createPayment,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'entityId': 'entity_1',
          'entityName': 'Client A',
          'amount': 100,
          'date': DateTime.utc(2026, 5, 20).toIso8601String(),
          'paymentMethod': 'cash',
        },
      );
      await queue.enqueue(
        type: OfflineActionTypes.createPayment,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'entityId': 'entity_2',
          'entityName': 'Client B',
          'amount': 120,
          'date': DateTime.utc(2026, 5, 21).toIso8601String(),
          'paymentMethod': 'bank',
        },
      );

      final repository = FirebasePaymentRepository(
        firestore,
        _MockWorkspaceMutationService(),
        queue,
      );

      final page = await repository.fetchPaymentsPage(
        'workspace_1',
        projectId: 'project_1',
        entityId: 'entity_1',
        paymentMethod: 'cash',
        cursor: null,
        pageSize: 20,
      );

      expect(page.items, hasLength(1));
      expect(page.items.first.entityId, 'entity_1');
      expect(page.items.first.paymentMethod, 'cash');
    },
  );

  test('createPayment forwards structured accounting fields', () async {
    final firestore = FakeFirebaseFirestore();
    final mutationService = _MockWorkspaceMutationService();
    when(
      () => mutationService.createPayment(
        workspaceId: any(named: 'workspaceId'),
        projectId: any(named: 'projectId'),
        amount: any(named: 'amount'),
        date: any(named: 'date'),
        paymentMethod: any(named: 'paymentMethod'),
        paymentStatus: any(named: 'paymentStatus'),
        description: any(named: 'description'),
        notes: any(named: 'notes'),
        entityId: any(named: 'entityId'),
        entityName: any(named: 'entityName'),
        entityType: any(named: 'entityType'),
        projectTotalPaymentsBefore: any(named: 'projectTotalPaymentsBefore'),
      ),
    ).thenAnswer((_) async => const MutationResult(queued: true));

    final repository = FirebasePaymentRepository(
      firestore,
      mutationService,
      queue,
    );

    await repository.createPayment(
      workspaceId: 'workspace_1',
      userId: 'user_1',
      projectId: 'project_1',
      amount: 900,
      date: DateTime.utc(2026, 5, 27),
      paymentMethod: 'bank',
      paymentStatus: PaymentStatuses.paid,
      description: 'Milestone transfer',
      notes: 'Invoice 12',
      entityId: 'entity_1',
      entityName: 'Client LLC',
      entityType: 'other',
    );

    verify(
      () => mutationService.createPayment(
        workspaceId: 'workspace_1',
        projectId: 'project_1',
        amount: 900,
        date: DateTime.utc(2026, 5, 27),
        paymentMethod: 'bank',
        paymentStatus: PaymentStatuses.paid,
        description: 'Milestone transfer',
        notes: 'Invoice 12',
        entityId: 'entity_1',
        entityName: 'Client LLC',
        entityType: 'other',
        projectTotalPaymentsBefore: null,
      ),
    ).called(1);
  });
}
