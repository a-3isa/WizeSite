import 'package:buildtrack_app/core/constants/app_routes.dart';
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
    final workersAsync = ref.watch(workersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.addWorker),
        icon: const Icon(Icons.add),
        label: const Text('Add Worker'),
      ),
      body: workersAsync.when(
        data: (workers) {
          if (workers.isEmpty) {
            return const Center(child: Text('No workers yet.'));
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
                    '${worker.phoneNumber} • Wage: ${worker.dailyWage.toStringAsFixed(0)}',
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
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Archive')),
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
    );
  }
}
