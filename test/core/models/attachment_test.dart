import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Attachment lifecycle', () {
    test(
      'serializes pending local attachment metadata without binary content',
      () {
        final attachment = Attachment(
          id: 'att_1',
          fileName: 'receipt.pdf',
          storagePath: '',
          contentType: 'application/pdf',
          uploadedAt: DateTime.utc(2026, 5, 27),
          localPath: r'C:\tmp\receipt.pdf',
          uploadStatus: AttachmentUploadStatus.pending,
          errorMessage: 'Waiting for connection',
        );

        final map = attachment.toMap();

        expect(map['localPath'], r'C:\tmp\receipt.pdf');
        expect(map['uploadStatus'], 'pending');
        expect(map['errorMessage'], 'Waiting for connection');
        expect(map.containsKey('bytes'), isFalse);
        expect(map.containsKey('base64'), isFalse);
      },
    );

    test('parses uploaded legacy attachment with uploaded status fallback', () {
      final attachment = Attachment.fromMap({
        'id': 'att_2',
        'fileName': 'photo.jpg',
        'storagePath': 'attachments/photo.jpg',
        'contentType': 'image/jpeg',
        'uploadedAt': '2026-05-27T00:00:00.000Z',
        'url': 'https://example.com/photo.jpg',
      });

      expect(attachment.uploadStatus, AttachmentUploadStatus.uploaded);
      expect(attachment.downloadUrl, 'https://example.com/photo.jpg');
      expect(attachment.localPath, isNull);
    });

    test('parses failed and missing local file states', () {
      final failed = Attachment.fromMap({
        'id': 'att_3',
        'fileName': 'invoice.pdf',
        'storagePath': '',
        'contentType': 'application/pdf',
        'uploadStatus': 'failed',
        'errorMessage': 'Upload failed',
      });
      final missing = Attachment.fromMap({
        'id': 'att_4',
        'fileName': 'missing.pdf',
        'storagePath': '',
        'contentType': 'application/pdf',
        'uploadStatus': 'missingLocalFile',
      });

      expect(failed.uploadStatus, AttachmentUploadStatus.failed);
      expect(failed.errorMessage, 'Upload failed');
      expect(missing.uploadStatus, AttachmentUploadStatus.missingLocalFile);
    });
  });
}
