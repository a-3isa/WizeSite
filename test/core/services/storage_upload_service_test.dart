import 'dart:io';
import 'dart:typed_data';

import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseStorage extends Mock implements FirebaseStorage {}

class _MockReference extends Mock implements Reference {}

void main() {
  late Directory tempDir;
  late _MockFirebaseStorage storage;
  late StorageUploadService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_upload_test_');
    storage = _MockFirebaseStorage();
    service = StorageUploadService(storage);
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

  test('Firebase retry-limit errors become retryable upload exceptions', () {
    final exception = StorageUploadException.fromFirebase(
      FirebaseException(
        plugin: 'firebase_storage',
        code: 'retry-limit-exceeded',
        message: 'network unavailable',
      ),
    );

    expect(exception.code, 'retry-limit-exceeded');
    expect(exception.retryable, isTrue);
    expect(exception.message, contains('connection'));
  });

  test('getDownloadUrl returns storage reference URL', () async {
    final reference = _MockReference();
    when(() => storage.ref('attachments/test.pdf')).thenReturn(reference);
    when(
      () => reference.getDownloadURL(),
    ).thenAnswer((_) async => 'https://example.com/attachments/test.pdf');

    final url = await service.getDownloadUrl('attachments/test.pdf');

    expect(url, 'https://example.com/attachments/test.pdf');
    verify(() => storage.ref('attachments/test.pdf')).called(1);
    verify(() => reference.getDownloadURL()).called(1);
  });

  test(
    'downloadAttachmentBytes returns bytes from storage reference',
    () async {
      final reference = _MockReference();
      final expectedBytes = Uint8List.fromList([1, 2, 3]);
      when(() => storage.ref('attachments/test.pdf')).thenReturn(reference);
      when(
        () => reference.getData(any()),
      ).thenAnswer((_) async => expectedBytes);

      final bytes = await service.downloadAttachmentBytes(
        'attachments/test.pdf',
      );

      expect(bytes, expectedBytes);
      verify(() => reference.getData(20 * 1024 * 1024)).called(1);
    },
  );
}
