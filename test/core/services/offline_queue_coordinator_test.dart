import 'dart:io';

import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/services/pending_attachment_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockStorageUploadService extends Mock implements StorageUploadService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late PendingAttachmentService pendingService;
  late _MockFirebaseAuth auth;
  late _MockUser user;
  late _MockStorageUploadService uploadService;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'offline_queue_coordinator_test_',
    );
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('offline_queue_coordinator_test');
    pendingService = PendingAttachmentService(box);
    auth = _MockFirebaseAuth();
    user = _MockUser();
    uploadService = _MockStorageUploadService();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('user_1');
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        pendingAttachmentServiceProvider.overrideWith(
          (ref) async => pendingService,
        ),
        storageUploadServiceProvider.overrideWithValue(uploadService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await box.close();
    await Hive.deleteBoxFromDisk('offline_queue_coordinator_test');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Attachment pendingAttachment(String path) {
    return Attachment(
      id: 'attachment_1',
      fileName: 'receipt.pdf',
      storagePath: '',
      contentType: 'application/pdf',
      uploadedAt: DateTime.utc(2026, 5, 28),
      localPath: path,
      uploadStatus: AttachmentUploadStatus.pending,
      size: 2048,
      uploadedBy: 'user_1',
    );
  }

  test('uploads pending attachments and clears retry records', () async {
    final file = File('${tempDir.path}/receipt.pdf');
    await file.writeAsBytes([1, 2, 3]);
    await pendingService.savePending(
      workspaceId: 'workspace_1',
      ownerType: 'expense',
      ownerId: 'expense_1',
      attachment: pendingAttachment(file.path),
    );
    when(
      () => uploadService.uploadAttachment(
        userId: 'user_1',
        localFilePath: file.path,
        fileName: 'receipt.pdf',
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer(
      (_) async => const UploadedAttachment(
        storagePath: 'attachments/user_1/receipt.pdf',
        downloadUrl: 'https://example.com/receipt.pdf',
        fileName: 'receipt.pdf',
        contentType: 'application/pdf',
        size: 3,
      ),
    );

    await container
        .read(offlineQueueCoordinatorProvider)
        .retryPendingAttachments();

    expect(await pendingService.listPending(), isEmpty);
    verify(
      () => uploadService.uploadAttachment(
        userId: 'user_1',
        localFilePath: file.path,
        fileName: 'receipt.pdf',
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).called(1);
  });

  test('marks missing local files as recoverable attachment state', () async {
    final path = '${tempDir.path}/missing.pdf';
    await pendingService.savePending(
      workspaceId: 'workspace_1',
      ownerType: 'expense',
      ownerId: 'expense_1',
      attachment: pendingAttachment(path),
    );
    when(
      () => uploadService.uploadAttachment(
        userId: 'user_1',
        localFilePath: path,
        fileName: 'receipt.pdf',
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenThrow(
      const StorageUploadException(
        'Attachment file not found.',
        code: 'missing-local-file',
        retryable: false,
      ),
    );

    await container
        .read(offlineQueueCoordinatorProvider)
        .retryPendingAttachments();

    final record = (await pendingService.listForOwner(
      ownerType: 'expense',
      ownerId: 'expense_1',
    )).single;
    expect(
      record.attachment.uploadStatus,
      AttachmentUploadStatus.missingLocalFile,
    );
  });
}
