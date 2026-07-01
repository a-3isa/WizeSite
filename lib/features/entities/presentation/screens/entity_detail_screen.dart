import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/attachment_validation_service.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class EntityDetailScreen extends ConsumerStatefulWidget {
  const EntityDetailScreen({required this.entityId, super.key});

  final String entityId;

  @override
  ConsumerState<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends ConsumerState<EntityDetailScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _pickAndUploadAttachments(List<Attachment> current) async {
    final l10n = AppLocalizations.of(context);
    final userId = ref.read(activeUserIdProvider);
    if (userId == null || userId.isEmpty) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: AttachmentValidationService.allowedExtensionsForPicker,
    );
    if (result == null) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final attachments = [...current];
      final invalidMessages = <String>[];
      for (final file in result.files) {
        final validationMessage =
            AttachmentValidationService.validatePickedFile(file);
        if (validationMessage != null) {
          invalidMessages.add(validationMessage);
          continue;
        }
        if (file.path == null) {
          invalidMessages.add(l10n.t('attachmentMissing'));
          continue;
        }
        final uploaded = await ref
            .read(storageUploadServiceProvider)
            .uploadAttachment(
              userId: userId,
              localFilePath: file.path!,
              fileName: file.name,
            );
        attachments.add(
          Attachment(
            id: const Uuid().v4(),
            fileName: uploaded.fileName,
            storagePath: uploaded.storagePath,
            contentType: uploaded.contentType,
            uploadedAt: DateTime.now(),
            downloadUrl: uploaded.downloadUrl,
            size: uploaded.size,
            uploadedBy: userId,
          ),
        );
      }
      await ref
          .read(entityRepositoryProvider)
          .saveAttachments(
            entityId: widget.entityId,
            attachments: attachments
                .map((attachment) => attachment.toMap())
                .toList(growable: false),
          );
      if (mounted && invalidMessages.isNotEmpty) {
        setState(() => _error = invalidMessages.join('\n'));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = appErrorMessage(l10n, error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('entitySummary'))),
      body: FutureBuilder(
        future: ref
            .read(entityRepositoryProvider)
            .getEntityById(widget.entityId),
        builder: (context, snapshot) {
          final entity = snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              entity == null) {
            return const AppLoadingSkeleton(lineCount: 8);
          }
          if (entity == null) {
            return Center(child: Text(l10n.t('noDataYet')));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(entity.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(entity.type),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () => _pickAndUploadAttachments(entity.attachments),
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
                label: Text(l10n.t('attachments')),
              ),
              const SizedBox(height: 12),
              if (entity.attachments.isEmpty)
                Text(l10n.t('noDataYet'))
              else
                ...entity.attachments.map(
                  (attachment) =>
                      AttachmentTile(attachment: attachment, canAccess: true),
                ),
            ],
          );
        },
      ),
    );
  }
}
