import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/core/services/workspace_mutation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final pendingSyncCount = ref.watch(offlinePendingCountProvider);
    final deadLetterCount = ref.watch(offlineDeadLetterCountProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final subscriptionAsync = ref.watch(currentSubscriptionStreamProvider);
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    final locale = Localizations.localeOf(context).languageCode;
    final snapshotAsync = workspaceId == null || workspaceId.isEmpty
        ? const AsyncValue<DashboardSnapshot>.data(
            DashboardSnapshot(
              hasFinancialAccess: false,
              totalProjects: 0,
              activeProjects: 0,
              totalExpenses: 0,
              totalIncome: 0,
              weeklyExpenses: 0,
              weeklyIncome: 0,
              topCategory: null,
              topEntity: null,
              recentTransactions: [],
            ),
          )
        : ref.watch(dashboardSnapshotProvider(workspaceId));

    Future<void> refresh() async {
      if (workspaceId != null && workspaceId.isNotEmpty) {
        ref.invalidate(dashboardSnapshotProvider(workspaceId));
      }
      ref.invalidate(notificationItemsProvider);
      ref.invalidate(currentSubscriptionStreamProvider);
      await Future.wait([
        if (workspaceId != null && workspaceId.isNotEmpty)
          ref.read(dashboardSnapshotProvider(workspaceId).future),
        ref.read(notificationItemsProvider.future),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const WorkspaceSwitcher(),
        actions: [
          Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: IconButton(
              key: const Key('qa_dashboard_notifications'),
              tooltip: l10n.t('notifications'),
              onPressed: () => context.push(AppRoutes.notifications),
              icon: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            key: const Key('qa_dashboard_settings'),
            tooltip: l10n.t('settings'),
            onPressed: () {
              ref.read(appPrefetcherProvider).warmSettings();
              context.push(AppRoutes.settings);
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (deadLetterCount > 0)
                _QueueStatusCard(
                  color: AppColors.danger,
                  icon: Icons.sync_problem_outlined,
                  message: l10n.t(
                    'offlineSyncFailed',
                    params: {'count': '$deadLetterCount'},
                  ),
                  actionLabel: l10n.t('syncStatus'),
                  onAction: () => context.push(AppRoutes.syncStatus),
                )
              else if (pendingSyncCount > 0)
                _QueueStatusCard(
                  color: AppColors.warning,
                  icon: Icons.cloud_upload_outlined,
                  message: l10n.t(
                    'offlineSyncPending',
                    params: {'count': '$pendingSyncCount'},
                  ),
                  actionLabel: l10n.t('syncStatus'),
                  onAction: () => context.push(AppRoutes.syncStatus),
                ),
              if (deadLetterCount > 0 || pendingSyncCount > 0)
                const SizedBox(height: 16),
              SectionHeader(title: l10n.t('resources')),
              const SizedBox(height: 12),
              const _ResourceLinks(),
              const SizedBox(height: 24),
              SectionHeader(title: l10n.t('overview')),
              const SizedBox(height: 12),
              snapshotAsync.whenStale(
                data: (snapshot) => DashboardFinancialSection(
                  snapshot: snapshot,
                  currency: currency,
                  locale: locale,
                ),
                loading: () => AppLoadingSkeleton(
                  semanticsLabel: l10n.t('loadingContent'),
                ),
                error: (error, _) => AppRecoverableError(
                  message: appErrorMessage(l10n, error),
                  onRetry: workspaceId == null
                      ? null
                      : () => ref.invalidate(
                          dashboardSnapshotProvider(workspaceId),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              subscriptionAsync.whenStale(
                data: (subscription) => subscription.tier == PlanTier.free
                    ? _UpgradeCard(
                        onTap: () => context.push(AppRoutes.subscriptionPlans),
                      )
                    : const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                loading: () => const AppLoadingSkeleton(
                  lineCount: 2,
                  padding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact workspace control rendered as the dashboard AppBar title.
///
/// Shows the active workspace name instantly from the cached summaries (no
/// loading skeleton). When the user belongs to more than one workspace it
/// becomes a dropdown with the current workspace shown first; otherwise it is
/// plain title text. Switching is optimistic and rolls back on failure.
class WorkspaceSwitcher extends ConsumerWidget {
  const WorkspaceSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspaces =
        ref.watch(userWorkspaceSummariesProvider).valueOrNull ??
        const <WorkspaceSummary>[];
    final activeWorkspaceName =
        ref.watch(activeWorkspaceNameProvider).valueOrNull?.trim() ?? '';

    WorkspaceSummary? current;
    for (final workspace in workspaces) {
      if (workspace.id == activeWorkspaceId) {
        current = workspace;
        break;
      }
    }
    final title = (current?.name.trim().isNotEmpty ?? false)
        ? current!.name.trim()
        : activeWorkspaceName.isNotEmpty
        ? activeWorkspaceName
        : l10n.t('home');

    if (workspaces.length < 2) {
      return Text(
        title,
        key: const Key('qa_workspace_switcher'),
        overflow: TextOverflow.ellipsis,
      );
    }

    return PopupMenuButton<String>(
      key: const Key('qa_workspace_dropdown'),
      tooltip: l10n.t('chooseWorkspace'),
      position: PopupMenuPosition.under,
      onSelected: (workspaceId) {
        if (workspaceId == activeWorkspaceId) {
          return;
        }
        _switchWorkspace(context, ref, workspaceId);
      },
      itemBuilder: (context) => [
        for (final workspace in workspaces)
          PopupMenuItem<String>(
            value: workspace.id,
            child: Row(
              children: [
                Icon(
                  workspace.id == activeWorkspaceId
                      ? Icons.check
                      : Icons.business_outlined,
                  size: 18,
                  color: AppColors.constructionOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(workspace.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Future<void> _switchWorkspace(
    BuildContext context,
    WidgetRef ref,
    String workspaceId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final previousWorkspaceId = ref.read(activeWorkspaceIdProvider);
    ref.read(activeWorkspaceIdProvider.notifier).state = workspaceId;
    try {
      final persistedWorkspaceId = await ref
          .read(workspaceMutationServiceProvider)
          .setActiveWorkspace(workspaceId: workspaceId);
      if (persistedWorkspaceId.isNotEmpty &&
          persistedWorkspaceId != workspaceId) {
        ref.read(activeWorkspaceIdProvider.notifier).state =
            persistedWorkspaceId;
      }
    } catch (error) {
      ref.read(activeWorkspaceIdProvider.notifier).state = previousWorkspaceId;
      messenger.showSnackBar(
        SnackBar(content: Text(appErrorMessage(l10n, error))),
      );
    }
  }
}

class DashboardFinancialSection extends StatelessWidget {
  const DashboardFinancialSection({
    required this.snapshot,
    required this.currency,
    required this.locale,
    super.key,
  });

  final DashboardSnapshot snapshot;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!snapshot.hasFinancialAccess) {
      return AppEmptyState(
        key: const Key('dashboard_financial_restricted'),
        icon: Icons.lock_outline,
        message: l10n.t('reportAccessDenied'),
      );
    }
    final isProfit = snapshot.net >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.35,
          children: [
            MetricCard(
              label: l10n.t('activeProjects'),
              value: '${snapshot.activeProjects}',
              color: AppColors.constructionOrange,
              icon: Icons.work_outline,
            ),
            MetricCard(
              label: l10n.t('totalExpenses'),
              value: Formatters.money(
                snapshot.totalExpenses,
                currencyCode: currency,
                locale: locale,
              ),
              color: AppColors.danger,
              icon: Icons.trending_down,
            ),
            MetricCard(
              label: l10n.t('totalIncome'),
              value: Formatters.money(
                snapshot.totalIncome,
                currencyCode: currency,
                locale: locale,
              ),
              color: AppColors.success,
              icon: Icons.trending_up,
            ),
            KeyedSubtree(
              key: Key(
                isProfit ? 'dashboard_net_profit' : 'dashboard_net_loss',
              ),
              child: MetricCard(
                label: l10n.t('netProfit'),
                value: Formatters.money(
                  snapshot.net,
                  currencyCode: currency,
                  locale: locale,
                ),
                color: isProfit ? AppColors.success : AppColors.danger,
                icon: isProfit ? Icons.trending_up : Icons.trending_down,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionHeader(title: l10n.t('weeklySummary')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: l10n.t('totalExpenses'),
                value: Formatters.money(
                  snapshot.weeklyExpenses,
                  currencyCode: currency,
                  locale: locale,
                ),
                color: AppColors.danger,
                icon: Icons.trending_down,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: l10n.t('totalIncome'),
                value: Formatters.money(
                  snapshot.weeklyIncome,
                  currencyCode: currency,
                  locale: locale,
                ),
                color: AppColors.success,
                icon: Icons.trending_up,
              ),
            ),
          ],
        ),
        // if (snapshot.topCategory != null || snapshot.topEntity != null) ...[
        //   const SizedBox(height: 20),
        //   Wrap(
        //     spacing: 12,
        //     runSpacing: 12,
        //     children: [
        //       if (snapshot.topCategory != null)
        //         Chip(
        //           avatar: const Icon(Icons.category_outlined, size: 18),
        //           label: Text(
        //             '${l10n.t('topCategory')}: ${snapshot.topCategory}',
        //           ),
        //         ),
        //       if (snapshot.topEntity != null)
        //         Chip(
        //           avatar: const Icon(Icons.business_outlined, size: 18),
        //           label: Text('${l10n.t('topEntity')}: ${snapshot.topEntity}'),
        //         ),
        //     ],
        //   ),
        // ],
      ],
    );
  }
}

class _ResourceLinks extends StatelessWidget {
  const _ResourceLinks();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.8,
      children: [
        _ResourceCard(
          qaKey: const Key('qa_resource_workers'),
          icon: Icons.engineering_outlined,
          label: l10n.t('workers'),
          color: AppColors.warning,
          onTap: () => context.push(AppRoutes.workers),
        ),
        _ResourceCard(
          qaKey: const Key('qa_resource_contractors'),
          icon: Icons.handyman_outlined,
          label: l10n.t('contractorsDirectory'),
          color: AppColors.constructionOrange,
          onTap: () => context.push(AppRoutes.contractorsDirectory),
        ),
        _ResourceCard(
          qaKey: const Key('qa_resource_equipment'),
          icon: Icons.construction_outlined,
          label: l10n.t('equipmentDirectory'),
          color: AppColors.success,
          onTap: () => context.push(AppRoutes.equipmentDirectory),
        ),
        _ResourceCard(
          qaKey: const Key('qa_resource_transport'),
          icon: Icons.local_shipping_outlined,
          label: l10n.t('transportDirectory'),
          color: AppColors.danger,
          onTap: () => context.push(AppRoutes.transportProvidersDirectory),
        ),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.qaKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Key qaKey;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        key: qaKey,
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueStatusCard extends StatelessWidget {
  const _QueueStatusCard({
    required this.color,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final Color color;
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: AppColors.constructionOrange,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.workspace_premium, color: Colors.white),
        title: Text(
          l10n.t('upgradeToPro'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          l10n.t('unlockHigherLimits'),
          style: const TextStyle(color: Colors.white),
        ),
        trailing: const Icon(Icons.arrow_forward, color: Colors.white),
      ),
    );
  }
}
