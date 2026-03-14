import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final paymentsProvider = StreamProvider<List<PaymentRecord>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref.watch(paymentRepositoryProvider).watchPayments(workspaceId);
});

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final paymentsAsync = ref.watch(paymentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('payments'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.addPayment),
        icon: const Icon(Icons.add),
        label: Text(l10n.t('addPayment')),
      ),
      body: paymentsAsync.when(
        data: (payments) {
          if (payments.isEmpty) {
            return Center(child: Text(l10n.t('noPaymentsYet')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final payment = payments[index];
              return Card(
                child: ListTile(
                  onTap: () => context.push('/payment/${payment.id}'),
                  title: Text(
                    '${payment.amount.toStringAsFixed(0)} | ${l10n.paymentMethodLabel(payment.paymentMethod)}',
                  ),
                  subtitle: Text(
                    l10n.t(
                      'projectDateWithValue',
                      params: {
                        'project': payment.projectId,
                        'date': payment.date.toIso8601String().split('T').first,
                      },
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        context.push('/payment/${payment.id}/edit');
                      } else {
                        await ref
                            .read(paymentRepositoryProvider)
                            .archivePayment(payment.id);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(l10n.t('edit')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.t('archive')),
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemCount: payments.length,
          );
        },
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
