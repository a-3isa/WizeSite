import 'package:buildtrack_app/core/services/attachment_file_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'attachment file types expose picker extensions and MIME types together',
    () {
      expect(AttachmentFileTypes.allowedExtensions, contains('.pdf'));
      expect(AttachmentFileTypes.allowedExtensions, contains('.docx'));
      expect(AttachmentFileTypes.allowedExtensionsForPicker, contains('pdf'));
      expect(AttachmentFileTypes.allowedExtensionsForPicker, contains('docx'));
      expect(
        AttachmentFileTypes.contentTypeForPath('receipt.pdf'),
        'application/pdf',
      );
      expect(
        AttachmentFileTypes.contentTypeForPath('invoice.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(AttachmentFileTypes.contentTypeForPath('malware.exe'), isNull);
    },
  );
}
