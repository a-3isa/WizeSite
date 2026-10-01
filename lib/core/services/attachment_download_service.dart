import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';

/// Resolves a short-lived signed URL through `getAttachmentDownloadUrl`. If
/// that fails for a reason other than authorization, a download URL stored on
/// the attachment (legacy records) is used instead.
Future<String> resolveAttachmentDownloadUrl({
  required CallableClient client,
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
          code.contains('unauthenticated') ||
          downloadUrl.isEmpty) {
        rethrow;
      }
    } catch (_) {
      if (downloadUrl.isEmpty) rethrow;
    }
  }
  return downloadUrl;
}
