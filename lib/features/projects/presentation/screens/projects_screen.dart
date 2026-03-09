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
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createProject),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
      body: SafeArea(
        child: projectsAsync.when(
          data: (projects) {
            if (projects.isEmpty) {
              return const Center(child: Text('No projects yet.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final project = projects[index];
                final color = project.netProfit >= 0
                    ? Colors.green
                    : Colors.red;
                return Card(
                  child: ListTile(
                    onTap: () => context.push('/project/${project.id}'),
                    title: Text(project.name),
                    subtitle: Text('${project.clientName} • ${project.status}'),
                    trailing: Text(
                      '${project.netProfit.toStringAsFixed(0)} EGP',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemCount: projects.length,
            );
          },
          error: (error, _) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
