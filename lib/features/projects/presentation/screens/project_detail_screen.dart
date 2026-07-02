import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/presentation/widgets/project_details_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final projectDetailsProvider = StreamProvider.family((ref, String projectId) {
  return ref.watch(projectRepositoryProvider).watchProject(projectId);
});

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final projectAsync = ref.watch(projectDetailsProvider(projectId));
    final prefetcher = ref.read(appPrefetcherProvider);
    final currency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';

    return AppBackScope(
      fallbackRoute: AppRoutes.projects,
      child: Scaffold(
        backgroundColor: context.tokens.bg,
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('projectDetails'),
          fallbackRoute: AppRoutes.projects,
          centerTitle: true,
        ),
        body: projectAsync.whenStale(
          data: (project) {
            if (project == null) {
              return Center(child: Text(l10n.t('projectNotFound')));
            }

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                ProjectHeader(project: project),
                const SizedBox(height: 24),
                FinancialGrid(project: project, currency: currency),
                const SizedBox(height: 32),
                ActionGrid(
                  onEdit: () =>
                      context.push(AppRoutes.projectEditPath(project.id)),
                  onArchive: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.t('archive')),
                        content: Text(l10n.t('confirm')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(l10n.t('cancel')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(l10n.t('archive')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(projectRepositoryProvider)
                          .archiveProject(project.id);
                      if (context.mounted) {
                        context.go(AppRoutes.projects);
                      }
                    }
                  },
                  onAddExpense: () {
                    prefetcher.warmAddEntry();
                    context.push(
                      AppRoutes.addExpensePath(projectId: project.id),
                    );
                  },
                  onAddPayment: () {
                    prefetcher.warmAddEntry();
                    context.push(
                      AppRoutes.addPaymentPath(projectId: project.id),
                    );
                  },
                  onViewExpenses: () =>
                      context.push(AppRoutes.projectExpensesPath(project.id)),
                  onViewPayments: () => context.push(
                    AppRoutes.paymentsPath(projectId: project.id),
                  ),
                  onAddWorkerEntry: () {
                    prefetcher.warmAddEntry();
                    context.push(
                      AppRoutes.workerEntryPath('new', projectId: project.id),
                    );
                  },
                  onViewWorkers: () => context.push(AppRoutes.workers),
                  onGenerateReport: () {
                    prefetcher.warmProjectReport(project.id);
                    context.push(AppRoutes.reportsPath(projectId: project.id));
                  },
                  onDelete: () async {
                    final controller = TextEditingController();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => StatefulBuilder(
                        builder: (context, setDialogState) {
                          final matches =
                              controller.text.trim() == project.name.trim();
                          return AlertDialog(
                            title: Text(l10n.t('delete')),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.t('confirmDeleteProjectCascade')),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.t('deleteProjectTypeNameToConfirm'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: controller,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    hintText: project.name,
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(l10n.t('cancel')),
                              ),
                              TextButton(
                                onPressed: matches
                                    ? () => Navigator.pop(context, true)
                                    : null,
                                child: Text(
                                  l10n.t('delete'),
                                  style: TextStyle(
                                    color: matches
                                        ? AppColors.danger
                                        : AppColors.textBody,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                    controller.dispose();
                    if (confirmed == true) {
                      await ref
                          .read(projectRepositoryProvider)
                          .deleteProject(project.id);
                      if (context.mounted) {
                        context.go(AppRoutes.projects);
                      }
                    }
                  },
                ),
                const SizedBox(height: 40),
              ],
            );
          },
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                const SizedBox(height: 16),
                Text(appErrorMessage(l10n, error)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(projectDetailsProvider(projectId)),
                  child: Text(l10n.t('retry')),
                ),
              ],
            ),
          ),
          loading: () => const AppLoadingSkeleton(lineCount: 8),
        ),
      ),
    );
  }
}
