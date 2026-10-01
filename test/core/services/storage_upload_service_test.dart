import 'dart:io';

import 'package:buildtrack_app/core/services/self_hosted_rpc_transport.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockTransport extends Mock implements SelfHostedRpcTransport {}

void main() {
  late Directory tempDir;
  late StorageUploadService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_upload_test_');
    service = StorageUploadService(_MockTransport());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('uploadAttachment throws when extension is unsupported', () async {
    final file = File('${tempDir.path}/receipt.exe');
    await file.writeAsBytes([1, 2, 3]);

    expect(
      () =>
          service.uploadAttachment(userId: 'user_1', localFilePath: file.path),
      throwsA(
        isA<StorageUploadException>()
            .having((error) => error.code, 'code', 'invalid-attachment')
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });

  test('contentTypeForAttachmentPath covers documents and archives', () {
    expect(
      StorageUploadService.contentTypeForAttachmentPath('receipt.pdf'),
      'application/pdf',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('photo.jpeg'),
      'image/jpeg',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('notes.txt'),
      'text/plain',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('items.csv'),
      'text/csv',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('invoice.docx'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('costs.xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('deck.pptx'),
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    );
    expect(
      StorageUploadService.contentTypeForAttachmentPath('backup.zip'),
      'application/zip',
    );
  });
}
