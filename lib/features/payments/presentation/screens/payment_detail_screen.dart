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
    final paymentAsync = ref.watch(paymentDetailsProvider(paymentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Details')),
      body: paymentAsync.when(
        data: (payment) {
          if (payment == null) {
            return const Center(child: Text('Payment not found.'));
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
                      Text('Amount: ${payment.amount.toStringAsFixed(0)}'),
                      Text('Method: ${payment.paymentMethod}'),
                      Text('Project: ${payment.projectId}'),
                      Text(
                        'Date: ${payment.date.toIso8601String().split('T').first}',
                      ),
                      Text(
                        'Notes: ${payment.notes.isEmpty ? '-' : payment.notes}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => context.push('/payment/${payment.id}/edit'),
                child: const Text('Edit'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await ref
                      .read(paymentRepositoryProvider)
                      .archivePayment(payment.id);
                  if (context.mounted) {
                    context.pop();
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Archive'),
              ),
            ],
          );
        },
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
