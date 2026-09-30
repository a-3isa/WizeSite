import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';

/// Resolves a short-lived Admin signed URL when online, then falls back to a
/// stored download URL only for non-authorization failures.
Future<String> resolveAttachmentDownloadUrl({
  required CallableClient client,
  required StorageUploadService storage,
  required String workspaceId,
  required Attachment attachment,
  required String defaultErrorMessage,
}) async {
  var downloadUrl = attachment.downloadUrl?.trim() ?? '';
  final storagePath = attachment.storagePath.trim();
  if (workspaceId.isNotEmpty && storagePath.isNotEmpty) {
    try {
      downloadUrl = await client.call<String>(
        functionName: 'getAttachmentDownloadUrl',
        payload: {'workspaceId': workspaceId, 'storagePath': storagePath},
        parseResult: (result) {
          if (result is Map) {
            return '${result['downloadUrl'] ?? ''}';
          }
          return '$result';
        },
        defaultErrorMessage: defaultErrorMessage,
      );
    } on CallableClientException catch (error) {
      final code = (error.code ?? '').toLowerCase().replaceAll('_', '-');
      if (code.contains('permission-denied') ||
          code.contains('unauthenticated')) {
        rethrow;
      }
      if (downloadUrl.isEmpty) {
        downloadUrl = await storage.getDownloadUrl(storagePath);
      }
    } catch (_) {
      if (downloadUrl.isEmpty) {
        downloadUrl = await storage.getDownloadUrl(storagePath);
      }
    }
  } else if (downloadUrl.isEmpty && storagePath.isNotEmpty) {
    downloadUrl = await storage.getDownloadUrl(storagePath);
  }
  return downloadUrl;
}
