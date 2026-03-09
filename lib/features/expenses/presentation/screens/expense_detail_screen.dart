import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final expenseDetailsProvider = FutureProvider.family((ref, String expenseId) {
  return ref.watch(expenseRepositoryProvider).getExpense(expenseId);
});

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({required this.expenseId, super.key});

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseDetailsProvider(expenseId));

    return Scaffold(
      appBar: AppBar(title: const Text('Expense Details')),
      body: expenseAsync.when(
        data: (expense) {
          if (expense == null) {
            return const Center(child: Text('Expense not found.'));
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
                      Text('Amount: ${expense.amount.toStringAsFixed(0)}'),
                      Text('Category: ${expense.category}'),
                      Text('Project: ${expense.projectId}'),
                      Text(
                        'Date: ${expense.date.toIso8601String().split('T').first}',
                      ),
                      Text(
                        'Supplier: ${expense.supplierName.isEmpty ? '-' : expense.supplierName}',
                      ),
                      Text(
                        'Notes: ${expense.notes.isEmpty ? '-' : expense.notes}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => context.push('/expense/${expense.id}/edit'),
                child: const Text('Edit'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await ref
                      .read(expenseRepositoryProvider)
                      .archiveExpense(expense.id);
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
