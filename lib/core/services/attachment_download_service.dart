import 'package:buildtrack_app/core/config/backend_config.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';

/// Resolves a short-lived signed URL when online, then falls back to a
/// stored download URL only for non-authorization failures.
///
/// Self-hosted builds have no Firebase Storage, so [allowStorageFallback]
/// defaults to false there and RPC failures surface as errors.
Future<String> resolveAttachmentDownloadUrl({
  required CallableClient client,
  required StorageUploadService storage,
  required String workspaceId,
  required Attachment attachment,
  required String defaultErrorMessage,
  bool? allowStorageFallback,
}) async {
  final storageFallback =
      allowStorageFallback ??
      !BackendConfig.fromEnvironment.useSelfHostedBackend;
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
        if (!storageFallback) rethrow;
        downloadUrl = await storage.getDownloadUrl(storagePath);
      }
    } catch (_) {
      if (downloadUrl.isEmpty) {
        if (!storageFallback) rethrow;
        downloadUrl = await storage.getDownloadUrl(storagePath);
      }
    }
  } else if (downloadUrl.isEmpty && storagePath.isNotEmpty && storageFallback) {
    downloadUrl = await storage.getDownloadUrl(storagePath);
  }
  return downloadUrl;
}
