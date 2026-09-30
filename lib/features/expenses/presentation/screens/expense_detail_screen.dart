import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/attachment_cache_service.dart';
import 'package:buildtrack_app/core/services/attachment_download_service.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/services/sync_error_classifier.dart';
import 'package:buildtrack_app/core/services/storage_upload_service.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final expenseDetailsProvider = FutureProvider.family((ref, String expenseId) {
  return ref.watch(expenseRepositoryProvider).getExpense(expenseId);
});

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    required this.expenseId,
    this.projectId,
    super.key,
  });

  final String expenseId;
  final String? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final expenseAsync = ref.watch(expenseDetailsProvider(expenseId));
    final storageUploadService = ref.read(storageUploadServiceProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final fallbackProjectId = projectId ?? expenseAsync.value?.projectId;

    Future<void> openAttachment(Attachment attachment) async {
      final workspaceId = ref.read(activeWorkspaceIdProvider) ?? '';
      try {
        await ref
            .read(attachmentCacheServiceProvider)
            .open(
              workspaceId: workspaceId,
              attachment: attachment,
              resolveUrl: () => resolveAttachmentDownloadUrl(
                client: ref.read(callableClientProvider),
                storage: storageUploadService,
                workspaceId: workspaceId,
                attachment: attachment,
                defaultErrorMessage: l10n.t('attachmentCannotOpen'),
              ),
            );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appErrorMessage(l10n, error))));
      }
    }

    final fallbackRoute =
        fallbackProjectId != null && fallbackProjectId.isNotEmpty
        ? AppRoutes.projectExpensesPath(fallbackProjectId)
        : AppRoutes.projects;

    return AppBackScope(
      fallbackRoute: fallbackRoute,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('expenseDetails'),
          fallbackRoute: fallbackRoute,
        ),
        body: expenseAsync.whenStale(
          data: (expense) {
            if (expense == null) {
              return Center(child: Text(l10n.t('expenseNotFound')));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t(
                            'amountWithValue',
                            params: {
                              'value': Formatters.money(
                                expense.amount,
                                currencyCode: expense.currency,
                                locale: locale,
                              ),
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'currencyWithValue',
                            params: {'value': expense.currency},
                          ),
                        ),
                        Text(
                          l10n.t(
                            'categoryWithValue',
                            params: {
                              'value': l10n.expenseCategoryLabel(
                                expense.category,
                              ),
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'projectWithValue',
                            params: {
                              'value': expense.projectName.isEmpty
                                  ? expense.projectId
                                  : expense.projectName,
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'dateWithValue',
                            params: {
                              'value': expense.date
                                  .toIso8601String()
                                  .split('T')
                                  .first,
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'supplierWithValue',
                            params: {
                              'value': expense.supplierName.isEmpty
                                  ? l10n.t('none')
                                  : expense.supplierName,
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'notesWithValue',
                            params: {
                              'value': expense.notes.isEmpty
                                  ? l10n.t('none')
                                  : expense.notes,
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'inputSourceWithValue',
                            params: {
                              'input': expense.inputMethod,
                              'source': expense.source.isEmpty
                                  ? l10n.t('none')
                                  : expense.source,
                            },
                          ),
                        ),
                        if (expense.attachments.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.t('attachments'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final attachment in expense.attachments.where(
                            _isImageAttachment,
                          ))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  attachment.downloadUrl ?? '',
                                  key: Key(
                                    'qa_expense_image_preview_${attachment.id}',
                                  ),
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    height: 120,
                                    color: context.tokens.surface3,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                            ),
                          Column(
                            children: expense.attachments
                                .map(
                                  (attachment) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: AttachmentTile(
                                        attachment: attachment,
                                        onOpen: () =>
                                            openAttachment(attachment),
                                        onDownload: () =>
                                            openAttachment(attachment),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => context.push(
                    AppRoutes.expenseEditPath(
                      expense.id,
                      projectId: fallbackProjectId ?? expense.projectId,
                    ),
                  ),
                  child: Text(l10n.t('edit')),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () async {
                    final workspaceId = ref.read(activeWorkspaceIdProvider);
                    final userId = ref.read(activeUserIdProvider);
                    if (workspaceId == null || userId == null) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text(l10n.t('pleaseLoginFirst'))),
                        );
                      return;
                    }
                    try {
                      final result = await ref
                          .read(expenseRepositoryProvider)
                          .createExpense(
                            workspaceId: workspaceId,
                            userId: userId,
                            projectId: expense.projectId,
                            projectName: expense.projectName,
                            category: expense.category,
                            amount: expense.amount,
                            currency: expense.currency,
                            date: DateTime.now(),
                            purpose: expense.purpose,
                            description: expense.description,
                            notes: expense.notes,
                            supplierName: expense.supplierName,
                            entityId: expense.entityId,
                            entityName: expense.entityName,
                            entityType: expense.entityType,
                            paymentMethod: expense.paymentMethod,
                            paymentStatus: expense.paymentStatus,
                            attachments: expense.attachments.isNotEmpty
                                ? expense.attachments
                                : null,
                          );
                      if (result.queued) {
                        await ref
                            .read(offlineQueueCoordinatorProvider)
                            .refreshCounts();
                        unawaited(
                          ref.read(offlineQueueCoordinatorProvider).drainNow(),
                        );
                        pushAppUiNotice(ref, l10n.t('queuedForSync'));
                      }
                      if (context.mounted) {
                        appNavigateBack(
                          context,
                          fallbackRoute: AppRoutes.projectExpensesPath(
                            expense.projectId,
                          ),
                        );
                      }
                    } on CallableClientException catch (e) {
                      if (SyncErrorClassifier.isQuotaLimitFailure(e)) {
                        if (context.mounted) {
                          context.push(
                            '${AppRoutes.subscriptionLimit}?limit=expensesPerMonth',
                          );
                        }
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(l10n.t('unexpectedErrorTryAgain')),
                            ),
                          );
                      }
                    }
                  },
                  child: Text(l10n.t('duplicate')),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.t('archive')),
                        content: Text(l10n.t('confirmArchiveExpense')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(l10n.t('cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(l10n.t('archive')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      final result = await ref
                          .read(expenseRepositoryProvider)
                          .archiveExpense(expense.id);
                      if (result.queued) {
                        await ref
                            .read(offlineQueueCoordinatorProvider)
                            .refreshCounts();
                        unawaited(
                          ref.read(offlineQueueCoordinatorProvider).drainNow(),
                        );
                        pushAppUiNotice(ref, l10n.t('queuedForSync'));
                      }
                      if (context.mounted) {
                        appNavigateBack(
                          context,
                          fallbackRoute: AppRoutes.projectExpensesPath(
                            expense.projectId,
                          ),
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: context.tokens.expense,
                    foregroundColor: context.tokens.onAccent,
                  ),
                  child: Text(l10n.t('archive')),
                ),
              ],
            );
          },
          error: (error, _) =>
              Center(child: Text(appErrorMessage(l10n, error))),
          loading: () => const AppLoadingSkeleton(lineCount: 8),
        ),
      ),
    );
  }

  bool _isImageAttachment(Attachment attachment) {
    final contentType = attachment.contentType.toLowerCase();
    if (contentType.startsWith('image/')) {
      return attachment.downloadUrl?.trim().isNotEmpty == true;
    }
    final fileName = attachment.fileName.toLowerCase();
    return attachment.downloadUrl?.trim().isNotEmpty == true &&
        (fileName.endsWith('.png') ||
            fileName.endsWith('.jpg') ||
            fileName.endsWith('.jpeg') ||
            fileName.endsWith('.webp'));
  }
}
