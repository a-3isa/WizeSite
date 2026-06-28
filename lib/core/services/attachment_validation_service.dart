import 'dart:io';

import 'package:buildtrack_app/core/services/attachment_file_types.dart';
import 'package:file_picker/file_picker.dart';

class AttachmentValidationService {
  const AttachmentValidationService._();

  static const int maxFileBytes = 10 * 1024 * 1024;

  static const List<String> allowedExtensions =
      AttachmentFileTypes.allowedExtensions;

  static const List<String> allowedExtensionsForPicker =
      AttachmentFileTypes.allowedExtensionsForPicker;

  static bool isSupportedExtension(String extension) {
    return AttachmentFileTypes.isSupportedExtension(extension);
  }

  static String? validatePickedFile(PlatformFile file) {
    final extension = AttachmentFileTypes.extensionOf(file.name);
    if (!isSupportedExtension(extension)) {
      return 'Unsupported attachment type: $extension. Use PDF, image, document, spreadsheet, or ZIP files.';
    }
    if (file.size > maxFileBytes) {
      return 'Attachment "${file.name}" is too large. Maximum file size is 10 MB.';
    }
    return null;
  }

  static Future<String?> validateLocalFile(String localFilePath) async {
    final extension = AttachmentFileTypes.extensionOf(localFilePath);
    if (!isSupportedExtension(extension)) {
      return 'Unsupported attachment type: $extension. Use PDF, image, document, spreadsheet, or ZIP files.';
    }
    final file = File(localFilePath);
    final exists = await file.exists();
    if (!exists) {
      return 'Attachment file not found.';
    }
    final size = await file.length();
    if (size > maxFileBytes) {
      return 'Attachment "${file.uri.pathSegments.last}" is too large. Maximum file size is 10 MB.';
    }
    return null;
  }
}
