import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final projectsProvider = StreamProvider<List<Project>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref.watch(projectRepositoryProvider).watchProjects(workspaceId);
});

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('projects'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createProject),
        icon: const Icon(Icons.add),
        label: Text(
          l10n.t('newProject'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: projectsAsync.when(
          data: (projects) {
            if (projects.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 64,
                      color: AppColors.borderGrey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.t('noProjectsYet'),
                      style: TextStyle(color: AppColors.textBody, fontSize: 16),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemBuilder: (context, index) {
                final project = projects[index];
                final positiveProfit = project.netProfit >= 0;
                final profitColor = positiveProfit
                    ? AppColors.success
                    : AppColors.danger;

                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push('/project/${project.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.constructionOrange.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.architecture,
                              color: AppColors.constructionOrange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      size: 14,
                                      color: AppColors.textBody,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      project.clientName,
                                      style: TextStyle(
                                        color: AppColors.textBody,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: project.status == 'active'
                                            ? AppColors.successLight
                                            : AppColors.surfaceGrey,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        l10n.projectStatusLabel(project.status),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: project.status == 'active'
                                              ? AppColors.success
                                              : AppColors.textBody,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${project.netProfit.toStringAsFixed(0)} EGP',
                                style: TextStyle(
                                  color: profitColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                positiveProfit
                                    ? l10n.t('profit')
                                    : l10n.t('loss'),
                                style: TextStyle(
                                  color: AppColors.textBody,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemCount: projects.length,
            );
          },
          error: (error, _) => Center(
            child: Text(
              error.toString(),
              style: TextStyle(color: AppColors.danger),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
