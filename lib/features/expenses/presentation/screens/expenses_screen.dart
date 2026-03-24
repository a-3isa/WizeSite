import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final projectExpensesProvider = StreamProvider.family<List<Expense>, String>((
  ref,
  projectId,
) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref
      .watch(expenseRepositoryProvider)
      .watchExpenses(workspaceId, projectId);
});

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final expensesAsync = ref.watch(projectExpensesProvider(projectId));
    return AppBackScope(
      fallbackRoute: AppRoutes.projectDetailPath(projectId),
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('expenseList'),
          fallbackRoute: AppRoutes.projectDetailPath(projectId),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              context.push(AppRoutes.addExpensePath(projectId: projectId)),
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
                    onTap: () => context.push(
                      AppRoutes.expenseDetailPath(
                        expense.id,
                        projectId: projectId,
                      ),
                    ),
                    title: Text(
                      '${expense.amount.toStringAsFixed(0)} ${expense.currency} | ${l10n.expenseCategoryLabel(expense.category)}',
                    ),
                    subtitle: Text(
                      l10n.t(
                        'projectDateWithValue',
                        params: {
                          'project': projectLabel,
                          'date': expense.date
                              .toIso8601String()
                              .split('T')
                              .first,
                        },
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          context.push(
                            AppRoutes.expenseEditPath(
                              expense.id,
                              projectId: projectId,
                            ),
                          );
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
      ),
    );
  }
}
