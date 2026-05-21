import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
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
}
