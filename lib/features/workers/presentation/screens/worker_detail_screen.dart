import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final workerDetailsProvider = FutureProvider.family((ref, String workerId) {
  return ref.watch(workerRepositoryProvider).getWorker(workerId);
});

final workerEntriesProvider =
    StreamProvider.family<List<WorkerEntryRecord>, String>((ref, workerId) {
      final workspaceId = ref.watch(activeWorkspaceIdProvider);
      if (workspaceId == null || workspaceId.isEmpty) {
        return const Stream.empty();
      }
      return ref
          .watch(workerEntryRepositoryProvider)
          .watchEntriesByWorker(workspaceId: workspaceId, workerId: workerId);
    });

class WorkerDetailScreen extends ConsumerWidget {
  const WorkerDetailScreen({required this.workerId, super.key});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workerAsync = ref.watch(workerDetailsProvider(workerId));
    final entriesAsync = ref.watch(workerEntriesProvider(workerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Worker Details')),
      body: workerAsync.when(
        data: (worker) {
          if (worker == null) {
            return const Center(child: Text('Worker not found.'));
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
                      Text(
                        worker.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text('Phone: ${worker.phoneNumber}'),
                      Text(
                        'Daily Wage: ${worker.dailyWage.toStringAsFixed(0)}',
                      ),
                      Text(
                        'Type: ${worker.workerType.isEmpty ? '-' : worker.workerType}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () =>
                          context.push('/worker/${worker.id}/edit'),
                      child: const Text('Edit Worker'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () =>
                          context.push('/worker-entry/${worker.id}'),
                      child: const Text('Add Entry'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Recent Entries',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              entriesAsync.when(
                data: (entries) {
                  if (entries.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No entries yet.'),
                      ),
                    );
                  }
                  final total = entries.fold<double>(
                    0,
                    (sum, e) => sum + e.totalCost,
                  );
                  return Column(
                    children: [
                      Card(
                        child: ListTile(
                          title: const Text('Total Labor Cost'),
                          trailing: Text(total.toStringAsFixed(0)),
                        ),
                      ),
                      ...entries.map(
                        (entry) => Card(
                          child: ListTile(
                            title: Text(
                              '${entry.daysWorked} d × ${entry.dailyWage.toStringAsFixed(0)} = ${entry.totalCost.toStringAsFixed(0)}',
                            ),
                            subtitle: Text(
                              entry.date.toIso8601String().split('T').first,
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  context.push(
                                    '/worker-entry/${worker.id}',
                                    extra: {'entryId': entry.id},
                                  );
                                } else {
                                  await ref
                                      .read(workerEntryRepositoryProvider)
                                      .archiveEntry(entry.id);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Archive'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                error: (error, _) => Text(error.toString()),
                loading: () => const CircularProgressIndicator(),
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
