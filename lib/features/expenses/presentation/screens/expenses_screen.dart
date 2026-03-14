import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final expensesProvider = StreamProvider<List<Expense>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref.watch(expenseRepositoryProvider).watchExpenses(workspaceId);
});

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final expensesAsync = ref.watch(expensesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('expenses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.addExpense),
        icon: const Icon(Icons.add),
        label: Text(l10n.t('addExpense')),
      ),
      body: expensesAsync.when(
        data: (expenses) {
          if (expenses.isEmpty) {
            return Center(child: Text(l10n.t('noExpensesYet')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final expense = expenses[index];
              final projectLabel = expense.projectName.isEmpty
                  ? expense.projectId
                  : expense.projectName;
              return Card(
                child: ListTile(
                  onTap: () => context.push('/expense/${expense.id}'),
                  title: Text(
                    '${expense.amount.toStringAsFixed(0)} ${expense.currency} | ${l10n.expenseCategoryLabel(expense.category)}',
                  ),
                  subtitle: Text(
                    l10n.t(
                      'projectDateWithValue',
                      params: {
                        'project': projectLabel,
                        'date': expense.date.toIso8601String().split('T').first,
                      },
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        context.push('/expense/${expense.id}/edit');
                      } else if (value == 'delete') {
                        await ref
                            .read(expenseRepositoryProvider)
                            .archiveExpense(expense.id);
                      }
                    },
                    itemBuilder: (context) => [
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
            itemCount: expenses.length,
          );
        },
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
