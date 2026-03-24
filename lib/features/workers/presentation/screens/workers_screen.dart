import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final workersProvider = StreamProvider<List<WorkerProfile>>((ref) {
  final workspaceId = ref.watch(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.isEmpty) {
    return const Stream.empty();
  }
  return ref.watch(workerRepositoryProvider).watchWorkers(workspaceId);
});

class WorkersScreen extends ConsumerWidget {
  const WorkersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workersAsync = ref.watch(workersProvider);
    return AppBackScope(
      fallbackRoute: AppRoutes.projects,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('workers'),
          fallbackRoute: AppRoutes.projects,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.addWorker),
          icon: const Icon(Icons.add),
          label: Text(l10n.t('addWorkerTitle')),
        ),
        body: workersAsync.when(
          data: (workers) {
            if (workers.isEmpty) {
              return Center(child: Text(l10n.t('noWorkersYet')));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: workers.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final worker = workers[index];
                return Card(
                  child: ListTile(
                    onTap: () => context.push('/worker/${worker.id}'),
                    leading: const Icon(Icons.engineering),
                    title: Text(worker.name),
                    subtitle: Text(
                      '${worker.phoneNumber} | ${l10n.t('wageWithValue', params: {'value': worker.dailyWage.toStringAsFixed(0)})}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          context.push('/worker/${worker.id}/edit');
                        } else {
                          await ref
                              .read(workerRepositoryProvider)
                              .archiveWorker(worker.id);
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
            );
          },
          error: (error, _) => Center(child: Text(error.toString())),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}
