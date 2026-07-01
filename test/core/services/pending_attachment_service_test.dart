import 'dart:io';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/pending_attachment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;
  late PendingAttachmentService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'pending_attachment_service_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('pending_attachment_service_test');
    service = PendingAttachmentService(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('pending_attachment_service_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Attachment pendingAttachment({String id = 'attachment_1'}) {
    return Attachment(
      id: id,
      fileName: 'receipt.pdf',
      storagePath: '',
      contentType: 'application/pdf',
      uploadedAt: DateTime.utc(2026, 5, 27),
      localPath: r'C:\pending\receipt.pdf',
      uploadStatus: AttachmentUploadStatus.pending,
      size: 2048,
      uploadedBy: 'user_1',
    );
  }

  test('saves pending local attachment reference for an owner', () async {
    final record = await service.savePending(
      workspaceId: 'workspace_1',
      ownerType: 'expense',
      ownerId: 'expense_1',
      attachment: pendingAttachment(),
    );

    expect(record.id, 'expense:expense_1:attachment_1');
    expect(record.attachment.localPath, r'C:\pending\receipt.pdf');
    expect(record.attachment.uploadStatus, AttachmentUploadStatus.pending);

    final ownerRecords = await service.listForOwner(
      ownerType: 'expense',
      ownerId: 'expense_1',
    );

    expect(ownerRecords, hasLength(1));
    expect(ownerRecords.single.workspaceId, 'workspace_1');
  });

  test('lists only retryable pending attachment records', () async {
    await service.savePending(
      workspaceId: 'workspace_1',
      ownerType: 'expense',
      ownerId: 'expense_1',
      attachment: pendingAttachment(id: 'pending_1'),
    );
    await service.savePending(
      workspaceId: 'workspace_1',
      ownerType: 'payment',
      ownerId: 'payment_1',
      attachment: pendingAttachment(id: 'uploaded_1'),
    );
    await service.markUploaded(
      id: 'payment:payment_1:uploaded_1',
      storagePath: 'attachments/user/uploaded_1.pdf',
      downloadUrl: 'https://example.com/uploaded_1.pdf',
    );

    final pending = await service.listPending();

    expect(pending, hasLength(1));
    expect(pending.single.id, 'expense:expense_1:pending_1');
  });

  test(
    'records failed and missing local file states as recoverable metadata',
    () async {
      await service.savePending(
        workspaceId: 'workspace_1',
        ownerType: 'expense',
        ownerId: 'expense_1',
        attachment: pendingAttachment(),
      );

      await service.markFailed(
        id: 'expense:expense_1:attachment_1',
        message: 'Upload timed out.',
      );
      final failed = (await service.listForOwner(
        ownerType: 'expense',
        ownerId: 'expense_1',
      )).single;

      expect(failed.attachment.uploadStatus, AttachmentUploadStatus.failed);
      expect(failed.attachment.errorMessage, 'Upload timed out.');

      await service.markMissingLocalFile(id: failed.id);
      final missing = (await service.listForOwner(
        ownerType: 'expense',
        ownerId: 'expense_1',
      )).single;

      expect(
        missing.attachment.uploadStatus,
        AttachmentUploadStatus.missingLocalFile,
      );
      expect(missing.attachment.errorMessage, contains('not found'));
    },
  );

  test('clears uploaded attachment records after retry succeeds', () async {
    await service.savePending(
      workspaceId: 'workspace_1',
      ownerType: 'expense',
      ownerId: 'expense_1',
      attachment: pendingAttachment(),
    );

    await service.markUploadedAndRemove(
      id: 'expense:expense_1:attachment_1',
      storagePath: 'attachments/user_1/attachment_1.pdf',
      downloadUrl: 'https://example.com/attachment_1.pdf',
    );

    expect(
      await service.listForOwner(ownerType: 'expense', ownerId: 'expense_1'),
      isEmpty,
    );
    expect(await service.listPending(), isEmpty);
  });
}
