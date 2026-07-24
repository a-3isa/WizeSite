import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:intl/intl.dart';
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
import 'package:buildtrack_app/features/dashboard/presentation/widgets/project_selector_sheet.dart';
import 'package:buildtrack_app/features/notifications/data/notification_providers.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/settings/presentation/widgets/workspace_switcher_sheet.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

/// Currently selected project for the dashboard. `null` means "All Projects"
/// (workspace-wide aggregate).
final selectedDashboardProjectIdProvider = StateProvider<String?>(
  (ref) => null,
);

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
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';
    final locale = Localizations.localeOf(context).languageCode;

    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final rawSelectedProjectId = ref.watch(selectedDashboardProjectIdProvider);
    // Honour the selection only while it still belongs to the active workspace.
    Project? selectedProject;
    if (rawSelectedProjectId != null) {
      for (final project in projects) {
        if (project.id == rawSelectedProjectId) {
          selectedProject = project;
          break;
        }
      }
    }

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _DashboardProjectSelector(
              projects: projects,
              selectedProject: selectedProject,
            ),
          ),
        ),
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
                  color: context.tokens.expense,
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
                  color: context.tokens.warning,
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
              SectionHeader(title: l10n.t('overview')),
              const SizedBox(height: 12),
              if (selectedProject != null)
                ProjectFinancialSection(
                  project: selectedProject,
                  currency: currency,
                  workspaceId: workspaceId ?? '',
                )
              else
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
              SectionHeader(title: l10n.t('resources')),
              const SizedBox(height: 12),
              const _ResourceLinks(),
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

/// Project filter shown under the dashboard AppBar. Scopes all financial data
/// to a single project, or to "All Projects" (workspace aggregate) when null.
class _DashboardProjectSelector extends ConsumerWidget {
  const _DashboardProjectSelector({
    required this.projects,
    required this.selectedProject,
  });

  final List<Project> projects;
  final Project? selectedProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final label = selectedProject?.name.trim().isNotEmpty == true
        ? selectedProject!.name.trim()
        : l10n.t('allProjects');

    return Material(
      key: const Key('qa_dashboard_project_selector'),
      color: context.tokens.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showProjectSelectorSheet(
          context,
          ref,
          projects: projects,
          selectedProjectId: selectedProject?.id,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                Icons.work_outline,
                size: 18,
                color: context.tokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.t('project').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.tokens.accent,
                      ),
                    ),
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.tokens.text,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_drop_down, color: context.tokens.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Financial overview scoped to a single project: leads with the net-profit
/// hero, followed by the remaining-budget progress card, then a compact,
/// secondary contract-value line. Mirrors the project detail screen's hero
/// treatment so the visual language matches across screens (per the v2 UI
/// audit: Contract Value is a fixed, rarely-changing number and should not
/// compete with Net Profit / Remaining Budget for visual weight).
class ProjectFinancialSection extends ConsumerWidget {
  const ProjectFinancialSection({
    required this.project,
    required this.currency,
    required this.workspaceId,
    super.key,
  });

  final Project project;
  final String currency;
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final recentAsync = workspaceId.isEmpty
        ? const AsyncValue<List<DashboardTransactionRef>>.data(
            <DashboardTransactionRef>[],
          )
        : ref.watch(
            projectRecentTransactionsProvider((
              workspaceId: workspaceId,
              projectId: project.id,
            )),
          );
    final budgetBase = (project.budgetLimit != null && project.budgetLimit! > 0)
        ? project.budgetLimit!
        : project.contractValue;
    final hasBudget = budgetBase > 0;
    final rawRatio = hasBudget ? project.totalExpenses / budgetBase : 0.0;
    final ratio = hasBudget ? rawRatio.clamp(0.0, 1.0) : 0.0;
    final overBudget = hasBudget && project.totalExpenses > budgetBase;
    final progressColor = budgetProgressColor(context.tokens, rawRatio);
    final remaining = budgetBase - project.totalExpenses;
    final numberFormat = NumberFormat.decimalPattern(locale);
    final isProfit = project.netProfit >= 0;
    final netText =
        '${isProfit ? '' : '−'}${numberFormat.format(project.netProfit.abs())}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.t('showingDataForProject', params: {'project': project.name}),
            key: const Key('qa_dashboard_project_scope_caption'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.tokens.textMuted),
          ),
        ),
        HeroNetCard(
          title: l10n.t('netProfit'),
          net: netText,
          negative: !isProfit,
          currency: currency,
          income: numberFormat.format(project.totalPayments),
          expense: numberFormat.format(project.totalExpenses),
          incomeLabel: l10n.t('totalIncome'),
          expenseLabel: l10n.t('totalExpenses'),
        ),
        if (hasBudget) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.tokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.t('budgetUsed'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.tokens.text,
                      ),
                    ),
                    Text(
                      '${Formatters.money(project.totalExpenses, currencyCode: currency, locale: locale)} / ${Formatters.money(budgetBase, currencyCode: currency, locale: locale)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.tokens.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: context.tokens.surface3,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  overBudget
                      ? l10n.t('overBudget')
                      : '${(ratio * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: progressColor,
                  ),
                ),
                if (!overBudget) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${Formatters.money(remaining, currencyCode: currency, locale: locale)} ${l10n.t('remaining')}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: progressColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          key: const Key('qa_dashboard_project_contract_value'),
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 14,
              color: context.tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.t('contractValue'),
              style: TextStyle(fontSize: 12, color: context.tokens.textMuted),
            ),
            const SizedBox(width: 6),
            Text(
              Formatters.money(
                project.contractValue,
                currencyCode: currency,
                locale: locale,
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.tokens.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: SectionHeader(title: l10n.t('recentTransactions'))),
            TextButton(
              key: const Key('qa_dashboard_recent_see_all'),
              onPressed: () => context.go(AppRoutes.activity),
              child: Text(l10n.t('seeAll')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        recentAsync.when(
          data: (items) => items.isEmpty
              ? AppEmptyState(
                  key: const Key('qa_dashboard_project_recent_empty'),
                  icon: Icons.receipt_long_outlined,
                  message: l10n.t('noDataYet'),
                )
              : Container(
                  key: const Key('qa_dashboard_project_recent'),
                  decoration: BoxDecoration(
                    color: context.tokens.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.tokens.border),
                  ),
                  child: Column(
                    children: [
                      for (final item in items)
                        _ProjectRecentRow(
                          item: item,
                          currency: currency,
                          locale: locale,
                          isLast: item == items.last,
                        ),
                    ],
                  ),
                ),
          loading: () =>
              AppLoadingSkeleton(semanticsLabel: l10n.t('loadingContent')),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),
        SectionHeader(title: l10n.t('quickAdd')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            BuildChip(
              label: l10n.t('addExpense'),
              icon: Icons.north_east,
              onTap: () => context.push(AppRoutes.addExpense),
            ),
            BuildChip(
              label: l10n.t('addPayment'),
              icon: Icons.south_west,
              onTap: () => context.push(AppRoutes.addPayment),
            ),
            BuildChip(
              label: l10n.t('voiceExpense'),
              icon: Icons.mic,
              onTap: () => context.push(AppRoutes.voiceExpense),
            ),
          ],
        ),
      ],
    );
  }
}

/// One row of the project-scoped recent transactions list. Payments (funds in)
/// are shown green and positive; expenses (funds out) red and negative.
class _ProjectRecentRow extends StatelessWidget {
  const _ProjectRecentRow({
    required this.item,
    required this.currency,
    required this.locale,
    required this.isLast,
  });

  final DashboardTransactionRef item;
  final String currency;
  final String locale;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isPayment = item.type == 'payment';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MoneyRow(
        title: item.title.isNotEmpty ? item.title : '—',
        amount: NumberFormat.decimalPattern(locale).format(item.amount.abs()),
        currency: currency,
        kind: isPayment ? MoneyKind.income : MoneyKind.expense,
        showDivider: !isLast,
      ),
    );
  }
}

/// Compact workspace control rendered as the dashboard AppBar title.
///
/// Shows the active workspace name instantly from the cached summaries (no
/// loading skeleton). Always tappable — even with a single workspace — so
/// "create another workspace" stays reachable regardless of how many the
/// user already has. Opens the premium [showWorkspaceSwitcherSheet].
class WorkspaceSwitcher extends ConsumerWidget {
  const WorkspaceSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspaces =
        ref.watch(userWorkspaceSummariesProvider).value ??
        const <WorkspaceSummary>[];
    final activeWorkspaceName =
        ref.watch(activeWorkspaceNameProvider).value?.trim() ?? '';

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

    return InkWell(
      key: const Key('qa_workspace_dropdown'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => showWorkspaceSwitcherSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
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
    final numberFormat = NumberFormat.decimalPattern(locale);
    final netText =
        '${isProfit ? '' : '−'}${numberFormat.format(snapshot.net.abs())}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v2 hero: big net figure with income/expense split, keyed so tests
        // (and QA) can tell profit from loss without relying on color.
        KeyedSubtree(
          key: Key(isProfit ? 'dashboard_net_profit' : 'dashboard_net_loss'),
          child: HeroNetCard(
            title: l10n.t('netProfit'),
            net: netText,
            negative: !isProfit,
            currency: currency,
            income: numberFormat.format(snapshot.totalIncome),
            expense: numberFormat.format(snapshot.totalExpenses),
            incomeLabel: l10n.t('totalIncome'),
            expenseLabel: l10n.t('totalExpenses'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.apartment_outlined,
                label: l10n.t('activeProjects'),
                value: '${snapshot.activeProjects}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: Icons.work_outline,
                label: l10n.t('projects'),
                value: '${snapshot.totalProjects}',
                iconColor: context.tokens.income,
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
                color: context.tokens.expense,
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
                color: context.tokens.income,
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
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.4,
      children: [
        _ResourceCard(
          qaKey: const Key('qa_resource_workers'),
          icon: Icons.engineering_outlined,
          label: l10n.t('workers'),
          color: context.tokens.warning,
          onTap: () => context.push(AppRoutes.workers),
        ),
        _ResourceCard(
          qaKey: const Key('qa_resource_contractors'),
          icon: Icons.handyman_outlined,
          label: l10n.t('contractorsDirectory'),
          color: context.tokens.accent,
          onTap: () => context.push(AppRoutes.contractorsDirectory),
        ),
        _ResourceCard(
          qaKey: const Key('qa_resource_equipment'),
          icon: Icons.construction_outlined,
          label: l10n.t('equipmentDirectory'),
          color: context.tokens.income,
          onTap: () => context.push(AppRoutes.equipmentDirectory),
        ),
        _ResourceCard(
          qaKey: const Key('qa_resource_transport'),
          icon: Icons.local_shipping_outlined,
          label: l10n.t('transportDirectory'),
          color: context.tokens.expense,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
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
      color: context.tokens.accent,
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
