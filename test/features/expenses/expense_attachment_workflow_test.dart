import 'dart:io';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/offline_action_queue.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/local_fixture_store.dart';

class _MockWorkspaceMutationService extends Mock
    implements WorkspaceMutationService {}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late OfflineActionQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'expense_attachment_workflow_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('expense_attachment_actions_test');
    queue = OfflineActionQueue(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('expense_attachment_actions_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('createExpense includes attachment metadata in payload', () async {
    final firestore = await LocalFixtureStore.open();
    addTearDown(firestore.dispose);
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
        inputMethod: any(named: 'inputMethod'),
        transcript: any(named: 'transcript'),
        source: any(named: 'source'),
        storagePath: any(named: 'storagePath'),
        projectTotalExpensesBefore: any(named: 'projectTotalExpensesBefore'),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async => const MutationResult(queued: true));

    final repository = LocalExpenseRepository(
      mutationService,
      queue,
      Future.value(firestore.local.db),
    );

    final attachments = [
      Attachment(
        id: 'attach_1',
        fileName: 'receipt.pdf',
        storagePath: 'attachments/receipt.pdf',
        contentType: 'application/pdf',
        uploadedAt: DateTime.utc(2026, 5, 25),
        downloadUrl: 'https://example.com/receipt.pdf',
        size: 1024,
      ),
    ];

    await repository.createExpense(
      workspaceId: 'workspace_1',
      userId: 'user_1',
      projectId: 'project_1',
      category: 'materials',
      amount: 120.0,
      date: DateTime.utc(2026, 5, 25),
      attachments: attachments,
    );

    final captured = verify(
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
        inputMethod: any(named: 'inputMethod'),
        transcript: any(named: 'transcript'),
        source: any(named: 'source'),
        storagePath: any(named: 'storagePath'),
        projectTotalExpensesBefore: any(named: 'projectTotalExpensesBefore'),
        attachments: captureAny(named: 'attachments'),
      ),
    ).captured;

    expect(captured, hasLength(1));
    final payloadAttachments = captured.first as List<dynamic>;
    expect(payloadAttachments, hasLength(1));
    expect(
      payloadAttachments.first['downloadUrl'],
      'https://example.com/receipt.pdf',
    );
    expect(payloadAttachments.first['fileName'], 'receipt.pdf');
  });

  test(
    'updateExpense preserves existing attachments when attachments are null',
    () async {
      final firestore = await LocalFixtureStore.open();
      addTearDown(firestore.dispose);
      await firestore.collection('expenses').doc('expense_1').set({
        'workspaceId': 'workspace_1',
        'projectId': 'project_1',
        'category': 'materials',
        'amount': 100,
        'currency': 'EGP',
        'date': DateTime.utc(2026, 5, 24).toIso8601String(),
        'notes': 'Initial',
        'supplierName': 'Vendor A',
        'paymentMethod': 'cash',
        'isArchived': false,
        'attachments': [
          {
            'id': 'attach_1',
            'fileName': 'receipt.pdf',
            'storagePath': 'attachments/receipt.pdf',
            'contentType': 'application/pdf',
            'uploadedAt': DateTime.utc(2026, 5, 24).toIso8601String(),
            'downloadUrl': 'https://example.com/receipt.pdf',
            'size': 1024,
          },
        ],
      });

      final mutationService = _MockWorkspaceMutationService();
      when(
        () => mutationService.updateExpense(
          workspaceId: any(named: 'workspaceId'),
          expenseId: any(named: 'expenseId'),
          projectId: any(named: 'projectId'),
          category: any(named: 'category'),
          amount: any(named: 'amount'),
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
          attachments: any(named: 'attachments'),
          previousAmount: any(named: 'previousAmount'),
          previousDate: any(named: 'previousDate'),
          previousCategory: any(named: 'previousCategory'),
        ),
      ).thenAnswer((_) async => const MutationResult(queued: true));

      final repository = LocalExpenseRepository(
        mutationService,
        queue,
        Future.value(firestore.local.db),
      );

      await repository.updateExpense(
        expenseId: 'expense_1',
        category: 'materials',
        amount: 120.0,
        date: DateTime.utc(2026, 5, 25),
        notes: 'Updated',
        supplierName: 'Vendor A',
        paymentMethod: 'cash',
        attachments: null,
      );

      final captured = verify(
        () => mutationService.updateExpense(
          workspaceId: any(named: 'workspaceId'),
          expenseId: any(named: 'expenseId'),
          projectId: any(named: 'projectId'),
          category: any(named: 'category'),
          amount: any(named: 'amount'),
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
          attachments: captureAny(named: 'attachments'),
          previousAmount: any(named: 'previousAmount'),
          previousDate: any(named: 'previousDate'),
          previousCategory: any(named: 'previousCategory'),
        ),
      ).captured;

      expect(captured, hasLength(1));
      final payloadAttachments = captured.first as List<dynamic>;
      expect(payloadAttachments, hasLength(1));
      expect(
        payloadAttachments.first['downloadUrl'],
        'https://example.com/receipt.pdf',
      );
    },
  );

  test(
    'pending offline expense exposes local attachment retry metadata',
    () async {
      final firestore = await LocalFixtureStore.open();
      addTearDown(firestore.dispose);
      await queue.enqueue(
        type: OfflineActionTypes.createExpense,
        payload: {
          'workspaceId': 'workspace_1',
          'projectId': 'project_1',
          'category': 'materials',
          'amount': 120,
          'date': DateTime.utc(2026, 5, 25).toIso8601String(),
          'attachments': [
            {
              'id': 'attach_pending',
              'fileName': 'receipt.pdf',
              'storagePath': '',
              'contentType': 'application/pdf',
              'uploadedAt': DateTime.utc(2026, 5, 25).toIso8601String(),
              'localPath': r'C:\pending\receipt.pdf',
              'uploadStatus': 'pending',
            },
          ],
        },
      );

      final repository = LocalExpenseRepository(
        _MockWorkspaceMutationService(),
        queue,
        Future.value(firestore.local.db),
      );

      final page = await repository.fetchExpensesPage(
        'workspace_1',
        projectId: 'project_1',
      );

      expect(page.items, hasLength(1));
      expect(
        page.items.single.attachments.single.localPath,
        r'C:\pending\receipt.pdf',
      );
      expect(
        page.items.single.attachments.single.uploadStatus,
        AttachmentUploadStatus.pending,
      );
    },
  );
}
