import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final projectDetailsProvider = FutureProvider.family((ref, String projectId) {
  return ref.watch(projectRepositoryProvider).getProject(projectId);
});

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final projectAsync = ref.watch(projectDetailsProvider(projectId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('projectDetails'))),
      body: projectAsync.when(
        data: (project) {
          if (project == null) {
            return Center(child: Text(l10n.t('projectNotFound')));
          }
          final healthColor = project.netProfit >= 0
              ? AppColors.success
              : AppColors.danger;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: Text(project.name),
                  subtitle: Text(project.clientName),
                  trailing: Chip(
                    label: Text(l10n.projectStatusLabel(project.status)),
                    backgroundColor: project.status == 'active'
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t(
                          'contractValueLabel',
                          params: {
                            'value': project.contractValue.toStringAsFixed(0),
                          },
                        ),
                      ),
                      Text(
                        l10n.t(
                          'totalExpensesLabel',
                          params: {
                            'value': project.totalExpenses.toStringAsFixed(0),
                          },
                        ),
                      ),
                      Text(
                        l10n.t(
                          'totalIncomeLabel',
                          params: {
                            'value': project.totalPayments.toStringAsFixed(0),
                          },
                        ),
                      ),
                      Text(
                        l10n.t(
                          'netLabel',
                          params: {'value': project.netProfit.toStringAsFixed(0)},
                        ),
                        style: TextStyle(
                          color: healthColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        l10n.t(
                          'completionLabel',
                          params: {
                            'value':
                                project.completionPercentage.toStringAsFixed(0),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.push('/project/${project.id}/edit'),
                    icon: const Icon(Icons.edit),
                    label: Text(l10n.t('edit')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await ref
                          .read(projectRepositoryProvider)
                          .archiveProject(project.id);
                      if (context.mounted) {
                        context.go(AppRoutes.projects);
                      }
                    },
                    icon: const Icon(Icons.archive),
                    label: Text(l10n.t('archive')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.addExpense),
                    icon: const Icon(Icons.receipt_long),
                    label: Text(l10n.t('addExpense')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.addPayment),
                    icon: const Icon(Icons.payments),
                    label: Text(l10n.t('addPayment')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/expenses'),
                    icon: const Icon(Icons.list),
                    label: Text(l10n.t('expenseList')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/payments'),
                    icon: const Icon(Icons.list_alt),
                    label: Text(l10n.t('paymentList')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/worker-entry/new'),
                    icon: const Icon(Icons.engineering),
                    label: Text(l10n.t('addWorkerEntry')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.reports),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(l10n.t('generateReport')),
                  ),
                ],
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
