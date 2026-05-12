import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final paymentDetailsProvider = FutureProvider.family((ref, String paymentId) {
  return ref.watch(paymentRepositoryProvider).getPayment(paymentId);
});

class PaymentDetailScreen extends ConsumerWidget {
  const PaymentDetailScreen({required this.paymentId, super.key});

  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final paymentAsync = ref.watch(paymentDetailsProvider(paymentId));
    return AppBackScope(
      fallbackRoute: AppRoutes.payments,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('paymentDetails'),
          fallbackRoute: AppRoutes.payments,
        ),
        body: paymentAsync.when(
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
                              'value': payment.amount.toStringAsFixed(0),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () =>
                      context.push(AppRoutes.paymentEditPath(payment.id)),
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
                          fallbackRoute: AppRoutes.payments,
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(l10n.t('archive')),
                ),
              ],
            );
          },
          error: (error, _) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
