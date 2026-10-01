import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/models/attachment.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/attachment_cache_service.dart';
import 'package:buildtrack_app/core/services/attachment_download_service.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final paymentDetailsProvider = FutureProvider.family((ref, String paymentId) {
  return ref.watch(paymentRepositoryProvider).getPayment(paymentId);
});

class PaymentDetailScreen extends ConsumerWidget {
  const PaymentDetailScreen({
    required this.paymentId,
    this.projectId,
    super.key,
  });

  final String paymentId;
  final String? projectId;

  String _fallbackRoute() {
    if (projectId != null && projectId!.isNotEmpty) {
      return AppRoutes.paymentsPath(projectId: projectId);
    }
    return AppRoutes.payments;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final paymentAsync = ref.watch(paymentDetailsProvider(paymentId));
    final locale = Localizations.localeOf(context).languageCode;
    final currency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';

    final role = ref.watch(currentAccountingRoleProvider).value;
    if (role?.canAccessAccounting != true) {
      return AppBackScope(
        fallbackRoute: _fallbackRoute(),
        child: Scaffold(
          appBar: appBackAppBar(
            context: context,
            title: l10n.t('paymentDetails'),
            fallbackRoute: _fallbackRoute(),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(24),
              child: Text(l10n.t('reportAccessDenied')),
            ),
          ),
        ),
      );
    }

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

    return AppBackScope(
      fallbackRoute: _fallbackRoute(),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('paymentDetails'),
          fallbackRoute: _fallbackRoute(),
        ),
        body: paymentAsync.whenStale(
          data: (payment) {
            if (payment == null) {
              return Center(child: Text(l10n.t('paymentNotFound')));
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
                                payment.amount,
                                currencyCode: currency,
                                locale: locale,
                              ),
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'methodWithValue',
                            params: {
                              'value': l10n.paymentMethodLabel(
                                payment.paymentMethod,
                              ),
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'projectWithValue',
                            params: {'value': payment.projectId},
                          ),
                        ),
                        Text(
                          l10n.t(
                            'dateWithValue',
                            params: {
                              'value': payment.date
                                  .toIso8601String()
                                  .split('T')
                                  .first,
                            },
                          ),
                        ),
                        Text(
                          l10n.t(
                            'notesWithValue',
                            params: {
                              'value': payment.notes.isEmpty
                                  ? l10n.t('none')
                                  : payment.notes,
                            },
                          ),
                        ),
                        if (payment.attachments.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Attachments',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: payment.attachments
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
                    AppRoutes.paymentEditPath(payment.id, projectId: projectId),
                  ),
                  child: Text(l10n.t('edit')),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.t('archive')),
                        content: Text(l10n.t('confirmArchivePayment')),
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
                          .read(paymentRepositoryProvider)
                          .archivePayment(payment.id);
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
                          fallbackRoute: _fallbackRoute(),
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
}
