import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final archivedProjectsProvider = StreamProvider<List<Project>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref
      .watch(projectRepositoryProvider)
      .watchArchivedProjects(workspaceId);
});

class ArchivedProjectsScreen extends ConsumerWidget {
  const ArchivedProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(archivedProjectsProvider);

    return AppBackScope(
      fallbackRoute: AppRoutes.projects,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('archivedProjects'),
          fallbackRoute: AppRoutes.projects,
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
                        Icons.archive_outlined,
                        size: 64,
                        color: AppColors.borderGrey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.t('noArchivedProjects'),
                        style: TextStyle(
                          color: AppColors.textBody,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceGrey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.architecture,
                              color: AppColors.textBody,
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
                                Text(
                                  project.clientName,
                                  style: TextStyle(
                                    color: AppColors.textBody,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'delete') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(l10n.t('delete')),
                                    content: Text(l10n.t('confirm')),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(l10n.t('cancel')),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(
                                          l10n.t('delete'),
                                          style: const TextStyle(
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await ref
                                      .read(projectRepositoryProvider)
                                      .deleteProject(project.id);
                                }
                              } else if (value == 'unarchive') {
                                await ref
                                    .read(projectRepositoryProvider)
                                    .unarchiveProject(project.id);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'unarchive',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.unarchive_outlined,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(l10n.t('unarchive')),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: AppColors.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.t('delete'),
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
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
      ),
    );
  }
}
