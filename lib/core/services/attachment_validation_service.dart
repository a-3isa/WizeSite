import 'dart:io';

import 'package:file_picker/file_picker.dart';

class AttachmentValidationService {
  const AttachmentValidationService._();

  static const int maxFileBytes = 10 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    '.pdf',
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.txt',
    '.csv',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.zip',
  ];

  static const List<String> allowedExtensionsForPicker = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'txt',
    'csv',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'zip',
  ];

  static String _extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == path.length - 1) {
      return '';
    }
    return path.substring(dotIndex).toLowerCase();
  }

  static bool isSupportedExtension(String extension) {
    return allowedExtensions.contains(extension.toLowerCase());
  }

  static String? validatePickedFile(PlatformFile file) {
    final extension = _extensionOf(file.name);
    if (!isSupportedExtension(extension)) {
      return 'Unsupported attachment type: $extension. Use PDF, image, document, spreadsheet, or ZIP files.';
    }
    if (file.size > maxFileBytes) {
      return 'Attachment "${file.name}" is too large. Maximum file size is 10 MB.';
    }
    return null;
  }

  static Future<String?> validateLocalFile(String localFilePath) async {
    final extension = _extensionOf(localFilePath);
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
