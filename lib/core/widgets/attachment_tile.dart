import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:flutter/material.dart';

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    required this.attachment,
    this.canAccess = true,
    this.deniedMessage,
    this.onOpen,
    this.onDownload,
    this.onRemove,
    super.key,
  });

  final Attachment attachment;
  final bool canAccess;
  final String? deniedMessage;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;

  bool get _isImage => attachment.contentType.startsWith('image/');

  bool get _isPdf =>
      attachment.contentType == 'application/pdf' ||
      attachment.fileName.toLowerCase().endsWith('.pdf');

  IconData get _icon {
    if (_isImage) {
      return Icons.image;
    }
    if (_isPdf) {
      return Icons.picture_as_pdf;
    }
    if (attachment.contentType.contains('spreadsheet') ||
        attachment.fileName.toLowerCase().endsWith('.xls') ||
        attachment.fileName.toLowerCase().endsWith('.xlsx')) {
      return Icons.table_chart;
    }
    if (attachment.contentType.contains('word') ||
        attachment.fileName.toLowerCase().endsWith('.doc') ||
        attachment.fileName.toLowerCase().endsWith('.docx')) {
      return Icons.description;
    }
    return Icons.attach_file;
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _ensureCanOpen(BuildContext context) {
    if (!canAccess) {
      _showMessage(
        context,
        deniedMessage ?? AppLocalizations.of(context).t('attachmentOpenDenied'),
      );
      return false;
    }
    if (attachment.uploadStatus == AttachmentUploadStatus.missingLocalFile) {
      _showMessage(
        context,
        AppLocalizations.of(context).t('attachmentMissing'),
      );
      return false;
    }
    if (attachment.uploadStatus == AttachmentUploadStatus.pending ||
        attachment.uploadStatus == AttachmentUploadStatus.uploading) {
      _showMessage(
        context,
        AppLocalizations.of(context).t('attachmentPending'),
      );
      return false;
    }
    if ((attachment.downloadUrl ?? '').trim().isEmpty &&
        (attachment.localPath ?? '').trim().isEmpty) {
      _showMessage(
        context,
        AppLocalizations.of(context).t('attachmentCannotOpen'),
      );
      return false;
    }
    return true;
  }

  void _handleOpen(BuildContext context) {
    if (!_ensureCanOpen(context)) {
      return;
    }
    if (_isImage) {
      _showImagePreview(context);
      return;
    }
    onOpen?.call();
  }

  void _handleDownload(BuildContext context) {
    if (!_ensureCanOpen(context)) {
      return;
    }
    (onDownload ?? onOpen)?.call();
  }

  void _showImagePreview(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text(
                  attachment.fileName,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: l10n.t('downloadAttachment'),
                    onPressed: onDownload == null
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                            onDownload?.call();
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.t('closePreview'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.network(
                    attachment.downloadUrl ?? '',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Icon(Icons.broken_image, size: 48),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon),
      title: Text(attachment.fileName),
      subtitle: Text(attachment.contentType),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_isImage ? Icons.zoom_in : Icons.open_in_new),
            onPressed: () => _handleOpen(context),
            tooltip: _isImage
                ? l10n.t('previewAttachment')
                : l10n.t('openAttachment'),
          ),
          if (_isPdf || onDownload != null)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () => _handleDownload(context),
              tooltip: l10n.t('downloadAttachment'),
            ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onRemove,
              tooltip: l10n.t('removeAttachment'),
            ),
        ],
      ),
      onTap: () => _handleOpen(context),
    );
  }
}
