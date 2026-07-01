import 'dart:io';

import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'attachment_validation_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('validatePickedFile accepts supported file under size limit', () {
    final file = PlatformFile(name: 'receipt.pdf', size: 1024);
    final error = AttachmentValidationService.validatePickedFile(file);

    expect(error, isNull);
  });

  test('validatePickedFile rejects unsupported extension', () {
    final file = PlatformFile(name: 'malware.exe', size: 1024);
    final error = AttachmentValidationService.validatePickedFile(file);

    expect(error, isNotNull);
    expect(error, contains('Unsupported attachment type'));
  });

  test('validatePickedFile rejects oversized file', () {
    final file = PlatformFile(
      name: 'large.pdf',
      size: AttachmentValidationService.maxFileBytes + 1,
    );
    final error = AttachmentValidationService.validatePickedFile(file);

    expect(error, isNotNull);
    expect(error, contains('too large'));
  });

  test('validatePickedFiles separates valid files and validation messages', () {
    final valid = PlatformFile(
      name: 'receipt.pdf',
      size: 1024,
      path: '${tempDir.path}/receipt.pdf',
    );
    final unsupported = PlatformFile(
      name: 'malware.exe',
      size: 1024,
      path: '${tempDir.path}/malware.exe',
    );
    final pathless = PlatformFile(name: 'ignored.pdf', size: 1024);

    final result = AttachmentValidationService.validatePickedFiles([
      valid,
      unsupported,
      pathless,
    ]);

    expect(result.validFiles, [valid]);
    expect(result.invalidMessages, hasLength(1));
    expect(
      result.invalidMessages.single,
      contains('Unsupported attachment type'),
    );
  });

  test('validateLocalFile rejects missing file', () async {
    final missingPath = tempDir.uri.resolve('missing.pdf').toFilePath();
    final error = await AttachmentValidationService.validateLocalFile(
      missingPath,
    );

    expect(error, isNotNull);
    expect(error, contains('not found'));
  });

  test('validateLocalFile accepts existing supported file', () async {
    final file = File('${tempDir.path}/receipt.pdf');
    await file.writeAsBytes(List<int>.filled(32, 0));

    final error = await AttachmentValidationService.validateLocalFile(
      file.path,
    );

    expect(error, isNull);
  });
}
