import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/attachment_tile.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/workers/data/worker_repository.dart';
import 'package:buildtrack_app/features/workers/domain/worker_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
    final l10n = AppLocalizations.of(context);
    final workerAsync = ref.watch(workerDetailsProvider(workerId));
    final entriesAsync = ref.watch(workerEntriesProvider(workerId));
    final locale = Localizations.localeOf(context).languageCode;
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';

    return AppBackScope(
      fallbackRoute: AppRoutes.workers,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('workerDetails'),
          fallbackRoute: AppRoutes.workers,
        ),
        body: workerAsync.when(
          data: (worker) {
            if (worker == null) {
              return Center(child: Text(l10n.t('workerNotFound')));
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
                        Text(
                          l10n.t(
                            'phoneWithValue',
                            params: {'value': worker.phoneNumber},
                          ),
                        ),
                        Text(
                          worker.billingType == 'project'
                              ? l10n.t(
                                  'billingTypeWithValue',
                                  params: {
                                    'value': l10n.t('billingTypeProject'),
                                  },
                                )
                              : l10n.t(
                                  'dailyWageWithValue',
                                  params: {
                                    'value': Formatters.money(
                                      worker.dailyWage,
                                      currencyCode: currency,
                                      locale: locale,
                                    ),
                                  },
                                ),
                        ),
                        Text(
                          l10n.t(
                            'typeWithValue',
                            params: {
                              'value': worker.workerType.isEmpty
                                  ? l10n.t('none')
                                  : l10n.workerTypeLabel(worker.workerType),
                            },
                          ),
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
                            context.push(AppRoutes.workerEditPath(worker.id)),
                        child: Text(l10n.t('editWorker')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () =>
                            context.push(AppRoutes.workerEntryPath(worker.id)),
                        child: Text(l10n.t('addEntry')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => context.push(
                    AppRoutes.workerAccountingPath(
                      worker.id,
                      name: worker.name,
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(l10n.t('workerAccounting')),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.t('recentEntries'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                entriesAsync.when(
                  data: (entries) {
                    if (entries.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(l10n.t('noEntriesYet')),
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
                            title: Text(l10n.t('totalLaborCost')),
                            trailing: Text(
                              Formatters.money(
                                total,
                                currencyCode: currency,
                                locale: locale,
                              ),
                            ),
                          ),
                        ),
                        ...entries.map(
                          (entry) => Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      worker.billingType == 'project'
                                          ? l10n.t(
                                              'totalWageWithValue',
                                              params: {
                                                'value': Formatters.money(
                                                  entry.totalCost,
                                                  currencyCode: currency,
                                                  locale: locale,
                                                ),
                                              },
                                            )
                                          : l10n.t(
                                              'workerEntryLine',
                                              params: {
                                                'days': '${entry.daysWorked}',
                                                'wage': Formatters.money(
                                                  entry.dailyWage,
                                                  currencyCode: currency,
                                                  locale: locale,
                                                ),
                                                'total': Formatters.money(
                                                  entry.totalCost,
                                                  currencyCode: currency,
                                                  locale: locale,
                                                ),
                                              },
                                            ),
                                    ),
                                    subtitle: Text(
                                      entry.date
                                          .toIso8601String()
                                          .split('T')
                                          .first,
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          context.push(
                                            AppRoutes.workerEntryPath(
                                              worker.id,
                                            ),
                                            extra: {'entryId': entry.id},
                                          );
                                        } else {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: Text(l10n.t('archive')),
                                              content: Text(
                                                l10n.t(
                                                  'confirmArchiveWorkerEntry',
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: Text(l10n.t('cancel')),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: Text(
                                                    l10n.t('archive'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true) {
                                            final result = await ref
                                                .read(
                                                  workerEntryRepositoryProvider,
                                                )
                                                .archiveEntry(entry.id);
                                            if (result.queued) {
                                              await ref
                                                  .read(
                                                    offlineQueueCoordinatorProvider,
                                                  )
                                                  .refreshCounts();
                                              unawaited(
                                                ref
                                                    .read(
                                                      offlineQueueCoordinatorProvider,
                                                    )
                                                    .drainNow(),
                                              );
                                            }
                                          }
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
                                  if (entry.attachments.isNotEmpty) ...[
                                    const Divider(height: 1),
                                    ...entry.attachments.map(
                                      (attachment) => AttachmentTile(
                                        attachment: attachment,
                                        onOpen: () {
                                          final url =
                                              attachment.downloadUrl ??
                                              attachment.localPath ??
                                              '';
                                          if (url.isNotEmpty) {
                                            unawaited(
                                              launchUrlString(
                                                url,
                                                mode: LaunchMode
                                                    .externalApplication,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  error: (error, _) => Text(error.toString()),
                  loading: () => const SizedBox.shrink(),
                ),
              ],
            );
          },
          error: (error, _) => Center(child: Text(error.toString())),
          loading: () => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
