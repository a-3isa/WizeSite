import 'dart:io';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
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
    tempDir = await Directory.systemTemp.createTemp(
      'payment_attachment_workflow_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('payment_attachment_actions_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('payment_attachment_actions_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('createPayment includes attachment metadata in payload', () async {
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
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => const MutationResult(queued: true));

    final repository = FirebasePaymentRepository(
      firestore,
      mutationService,
      queue,
    );

    final attachments = [
      Attachment(
        id: 'attach_2',
        fileName: 'receipt.png',
        storagePath: 'attachments/receipt.png',
        contentType: 'image/png',
        uploadedAt: DateTime.utc(2026, 5, 25),
        downloadUrl: 'https://example.com/receipt.png',
        size: 2048,
      ),
    ];

    await repository.createPayment(
      workspaceId: 'workspace_1',
      userId: 'user_1',
      projectId: 'project_1',
      amount: 250.0,
      date: DateTime.utc(2026, 5, 25),
      paymentMethod: 'bank_transfer',
      attachments: attachments,
    );

    final captured = verify(
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
        attachments: captureAny(named: 'attachments'),
      ),
    ).captured;

    expect(captured, hasLength(1));
    final payloadAttachments = captured.first as List<dynamic>;
    expect(payloadAttachments, hasLength(1));
    expect(payloadAttachments.first['fileName'], 'receipt.png');
    expect(
      payloadAttachments.first['downloadUrl'],
      'https://example.com/receipt.png',
    );
  });

  test(
    'updatePayment preserves existing attachments when attachments are null',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('payments').doc('payment_1').set({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'amount': 250,
        'date': DateTime.utc(2026, 5, 24).toIso8601String(),
        'paymentMethod': 'bank_transfer',
        'notes': 'Initial payment',
        'isArchived': false,
        'attachments': [
          {
            'id': 'attach_2',
            'fileName': 'receipt.png',
            'storagePath': 'attachments/receipt.png',
            'contentType': 'image/png',
            'uploadedAt': DateTime.utc(2026, 5, 24).toIso8601String(),
            'downloadUrl': 'https://example.com/receipt.png',
            'size': 2048,
          },
        ],
      });

      final mutationService = _MockWorkspaceMutationService();
      when(
        () => mutationService.updatePayment(
          workspaceId: any(named: 'workspaceId'),
          paymentId: any(named: 'paymentId'),
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
          attachments: any(named: 'attachments'),
          previousAmount: any(named: 'previousAmount'),
          previousDate: any(named: 'previousDate'),
        ),
      ).thenAnswer((_) async => const MutationResult(queued: true));

      final repository = FirebasePaymentRepository(
        firestore,
        mutationService,
        queue,
      );

      await repository.updatePayment(
        paymentId: 'payment_1',
        amount: 300.0,
        date: DateTime.utc(2026, 5, 25),
        paymentMethod: 'bank_transfer',
        notes: 'Updated payment',
        attachments: null,
      );

      final captured = verify(
        () => mutationService.updatePayment(
          workspaceId: any(named: 'workspaceId'),
          paymentId: any(named: 'paymentId'),
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
          attachments: captureAny(named: 'attachments'),
          previousAmount: any(named: 'previousAmount'),
          previousDate: any(named: 'previousDate'),
        ),
      ).captured;

      expect(captured, hasLength(1));
      final payloadAttachments = captured.first as List<dynamic>;
      expect(payloadAttachments, hasLength(1));
      expect(payloadAttachments.first['fileName'], 'receipt.png');
    },
  );

  test(
    'pending offline payment exposes local attachment retry metadata',
    () async {
      final firestore = FakeFirebaseFirestore();
      await queue.enqueue(
        type: OfflineActionTypes.createPayment,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'amount': 250,
          'date': DateTime.utc(2026, 5, 25).toIso8601String(),
          'paymentMethod': 'bank_transfer',
          'attachments': [
            {
              'id': 'attach_pending',
              'fileName': 'receipt.png',
              'storagePath': '',
              'contentType': 'image/png',
              'uploadedAt': DateTime.utc(2026, 5, 25).toIso8601String(),
              'localPath': r'C:\pending\receipt.png',
              'uploadStatus': 'pending',
            },
          ],
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
      );

      expect(page.items, hasLength(1));
      expect(
        page.items.single.attachments.single.localPath,
        r'C:\pending\receipt.png',
      );
      expect(
        page.items.single.attachments.single.uploadStatus,
        AttachmentUploadStatus.pending,
      );
    },
  );
}
