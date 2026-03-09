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
    final projectAsync = ref.watch(projectDetailsProvider(projectId));
    return Scaffold(
      appBar: AppBar(title: const Text('Project Details')),
      body: projectAsync.when(
        data: (project) {
          if (project == null) {
            return const Center(child: Text('Project not found.'));
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
                    label: Text(project.status),
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
                        'Contract Value: ${project.contractValue.toStringAsFixed(0)}',
                      ),
                      Text(
                        'Total Expenses: ${project.totalExpenses.toStringAsFixed(0)}',
                      ),
                      Text(
                        'Total Income: ${project.totalPayments.toStringAsFixed(0)}',
                      ),
                      Text(
                        'Net: ${project.netProfit.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: healthColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Completion: ${project.completionPercentage.toStringAsFixed(0)}%',
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
                    label: const Text('Edit'),
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
                    label: const Text('Archive'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.addExpense),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Add Expense'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.addPayment),
                    icon: const Icon(Icons.payments),
                    label: const Text('Add Payment'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/expenses'),
                    icon: const Icon(Icons.list),
                    label: const Text('Expense List'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/payments'),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Payment List'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/worker-entry/new'),
                    icon: const Icon(Icons.engineering),
                    label: const Text('Add Worker Entry'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push(AppRoutes.reports),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Generate Report'),
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
