import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:intl/intl.dart';
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
        // Cash Collected is a one-time `.get()` (FutureProvider), not a live
        // listener (see dashboardCashCollectedProvider's doc comment) — it
        // only re-runs on mount or when explicitly invalidated here, so
        // pull-to-refresh is the mechanism that keeps it from going stale.
        ref.invalidate(dashboardCashCollectedProvider(workspaceId));
      }
      ref.invalidate(notificationItemsProvider);
      ref.invalidate(currentSubscriptionStreamProvider);
      await Future.wait([
        if (workspaceId != null && workspaceId.isNotEmpty) ...[
          ref.read(dashboardSnapshotProvider(workspaceId).future),
          ref.read(dashboardCashCollectedProvider(workspaceId).future),
        ],
        ref.read(notificationItemsProvider.future),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        // Premium two-line header: the workspace is a small tappable eyebrow,
        // the current project scope is the bold primary title — both open their
        // respective bottom sheets. Settings lives on the More tab, so the app
        // bar keeps only the notifications action for a clean, uncluttered look.
        title: DashboardHeader(
          projects: projects,
          selectedProject: selectedProject,
        ),
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
              _AlertsCard(
                workspaceId: workspaceId ?? '',
                projects: projects,
                currency: currency,
                locale: locale,
              ),
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
                    projects: projects,
                    currency: currency,
                    locale: locale,
                    workspaceId: workspaceId ?? '',
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
              // The resource directory (Workers/Contractors/Equipment/
              // Transport) lives on the More tab, not here — Home stays focused
              // on financial/operational stats. The worker-attendance and
              // payment-status cards below are derived stats, not directory
              // navigation, so they remain.
              _WorkerAttendanceCard(
                workspaceId: workspaceId ?? '',
                locale: locale,
              ),
              const SizedBox(height: 12),
              _PaymentStatusCard(
                workspaceId: workspaceId ?? '',
                currency: currency,
                locale: locale,
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

/// Project filter shown under the dashboard AppBar. Scopes all financial data
/// to a single project, or to "All Projects" (workspace aggregate) when null.
/// Premium dashboard header: a small tappable workspace eyebrow stacked over
/// the bold current-project title. The workspace opens the workspace switcher
/// sheet; the project opens the project selector sheet. Both live in the app
/// bar so Home's body starts straight at the financial overview.
class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({
    required this.projects,
    required this.selectedProject,
    super.key,
  });

  final List<Project> projects;
  final Project? selectedProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;

    // --- Workspace name (same resolution as the old WorkspaceSwitcher) ---
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
    final workspaceName = (current?.name.trim().isNotEmpty ?? false)
        ? current!.name.trim()
        : activeWorkspaceName.isNotEmpty
        ? activeWorkspaceName
        : l10n.t('home');

    final projectLabel = selectedProject?.name.trim().isNotEmpty == true
        ? selectedProject!.name.trim()
        : l10n.t('allProjects');

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Workspace eyebrow — small, muted, secondary.
        Semantics(
          button: true,
          label: '${l10n.t('workspace')}: $workspaceName',
          child: InkWell(
            key: const Key('qa_workspace_dropdown'),
            borderRadius: BorderRadius.circular(BuildTokens.pill),
            onTap: () => showWorkspaceSwitcherSheet(context),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(2, 2, 4, 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspaces_outline, size: 13, color: t.textMuted),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      workspaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, size: 15, color: t.textMuted),
                ],
              ),
            ),
          ),
        ),
        // Project scope — the bold primary title.
        Semantics(
          button: true,
          label: '${l10n.t('project')}: $projectLabel',
          child: InkWell(
            key: const Key('qa_dashboard_project_selector'),
            borderRadius: BorderRadius.circular(BuildTokens.pill),
            onTap: () => showProjectSelectorSheet(
              context,
              ref,
              projects: projects,
              selectedProjectId: selectedProject?.id,
            ),
            child: ConstrainedBox(
              // Keeps the primary tap target at/above the 48dp minimum.
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 4, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.work_outline, size: 20, color: t.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        projectLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: t.text,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 24, color: t.accent),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
    // Profit Margin KPI (v2 UI audit Task B4): net ÷ income for this project,
    // surfaced as a first-class stat next to the Net Profit hero. `null`
    // when income is zero — shown as an em dash rather than a NaN/Infinity
    // percentage.
    final profitMarginText = Formatters.profitMargin(
      project.netProfit,
      project.totalPayments,
    );

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
        const SizedBox(height: 12),
        StatTile(
          key: const Key('qa_dashboard_project_profit_margin'),
          icon: Icons.percent,
          label: l10n.t('profitMargin'),
          value: profitMarginText ?? '—',
          valueColor: profitMarginText == null
              ? null
              : (isProfit ? context.tokens.income : context.tokens.expense),
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
                AnimatedProgressBar(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: context.tokens.surface3,
                  color: progressColor,
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

class DashboardFinancialSection extends ConsumerWidget {
  const DashboardFinancialSection({
    required this.snapshot,
    required this.projects,
    required this.currency,
    required this.locale,
    required this.workspaceId,
    super.key,
  });

  /// Only its `hasFinancialAccess` flag is used, to gate the whole section.
  /// The financial figures below are derived live from [projects] and the
  /// weekly providers instead of the `workspace_metrics` aggregate doc this
  /// snapshot carries — that doc can lag behind (e.g. reflect only some
  /// projects), which made the "All Projects" overview show stale totals and
  /// a project count of 1 even with three active projects.
  final DashboardSnapshot snapshot;

  /// Active (non-archived), metrics-merged projects. The workspace-wide
  /// overview (net / income / expenses / counts / margin) is summed from these
  /// so it always agrees with the Projects list and self-heals if the
  /// aggregate doc is stale.
  final List<Project> projects;
  final String currency;
  final String locale;

  /// Used to fetch the current- and previous-week comparison totals that power
  /// the weekly summary + ▲/▼ trend indicators below. An empty id (e.g. no
  /// active workspace, or a standalone widget test) skips those lookups.
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (!snapshot.hasFinancialAccess) {
      return AppEmptyState(
        key: const Key('dashboard_financial_restricted'),
        icon: Icons.lock_outline,
        message: l10n.t('reportAccessDenied'),
      );
    }

    // Workspace-wide totals derived live from the (metrics-merged) project
    // list rather than the stale workspace_metrics aggregate doc.
    final totalIncome = projects.fold<double>(
      0,
      (sum, p) => sum + p.totalPayments,
    );
    final totalExpenses = projects.fold<double>(
      0,
      (sum, p) => sum + p.totalExpenses,
    );
    final net = totalIncome - totalExpenses;
    final totalProjects = projects.length;
    final activeProjects = projects
        .where((p) => p.status.trim().toLowerCase() == 'active')
        .length;

    // Current-week totals from the live weekly stream (not the aggregate doc),
    // so the "Last 7 Days" figures and their trends are accurate too.
    final thisWeek = workspaceId.isEmpty
        ? const AsyncValue<Map<String, num>>.data(<String, num>{})
        : ref.watch(dashboardWeeklySummaryProvider(workspaceId));
    final thisWeekData = thisWeek.value ?? const <String, num>{};
    final weeklyExpenses = (thisWeekData['weeklyExpenses'] ?? 0).toDouble();
    final weeklyIncome = (thisWeekData['weeklyIncome'] ?? 0).toDouble();

    final previousWeek = workspaceId.isEmpty
        ? const AsyncValue<Map<String, num>>.data(<String, num>{})
        : ref.watch(dashboardPreviousWeekSummaryProvider(workspaceId));
    final previousWeekData = previousWeek.value ?? const <String, num>{};
    final previousWeekExpenses = (previousWeekData['previousWeekExpenses'] ?? 0)
        .toDouble();
    final previousWeekIncome = (previousWeekData['previousWeekIncome'] ?? 0)
        .toDouble();
    final expenseTrend = _weeklyTrendIndicator(
      context: context,
      l10n: l10n,
      thisWeek: weeklyExpenses,
      lastWeek: previousWeekExpenses,
      increaseIsGood: false,
    );
    final incomeTrend = _weeklyTrendIndicator(
      context: context,
      l10n: l10n,
      thisWeek: weeklyIncome,
      lastWeek: previousWeekIncome,
      increaseIsGood: true,
    );
    final isProfit = net >= 0;
    final numberFormat = NumberFormat.decimalPattern(locale);
    final netText = '${isProfit ? '' : '−'}${numberFormat.format(net.abs())}';
    // Profit Margin KPI (v2 UI audit Task B4): net ÷ income as a percentage,
    // surfaced as a first-class stat alongside Active Projects / Projects
    // rather than requiring readers to do the division themselves from the
    // hero card's income/expense split. `null` when income is zero — margin
    // is undefined without revenue, so the tile shows an em dash instead of
    // a NaN/Infinity percentage.
    final profitMarginText = Formatters.profitMargin(net, totalIncome);
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
            income: numberFormat.format(totalIncome),
            expense: numberFormat.format(totalExpenses),
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
                value: '$activeProjects',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: Icons.work_outline,
                label: l10n.t('projects'),
                value: '$totalProjects',
                iconColor: context.tokens.income,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                key: const Key('qa_dashboard_profit_margin'),
                icon: Icons.percent,
                label: l10n.t('profitMargin'),
                value: profitMarginText ?? '—',
                valueColor: profitMarginText == null
                    ? null
                    : (isProfit
                          ? context.tokens.income
                          : context.tokens.expense),
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
                  weeklyExpenses,
                  currencyCode: currency,
                  locale: locale,
                ),
                color: context.tokens.expense,
                icon: Icons.trending_down,
                trend: expenseTrend,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                label: l10n.t('totalIncome'),
                value: Formatters.money(
                  weeklyIncome,
                  currencyCode: currency,
                  locale: locale,
                ),
                color: context.tokens.income,
                icon: Icons.trending_up,
                trend: incomeTrend,
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

/// Builds the compact ▲/▼ week-over-week trend badge for a single financial
/// figure (v2 UI audit Problem 7: "Every financial card should optionally
/// display: ▲ 12% / ▼ 8% — Compared to last week"). Returns null when there's
/// no meaningful baseline to compare against (last week's total is zero, or
/// the two weeks are identical), rather than showing a nonsensical or
/// no-op indicator.
///
/// [increaseIsGood] flips the color mapping: for income/net an increase is
/// favorable (green), while for expenses an increase is unfavorable (red)
/// even though the arrow still points up — the arrow direction always
/// reflects the raw number, only the color reflects whether that's good news.
Widget? _weeklyTrendIndicator({
  required BuildContext context,
  required AppLocalizations l10n,
  required double thisWeek,
  required double lastWeek,
  required bool increaseIsGood,
}) {
  if (lastWeek == 0) return null;
  final percentChange = (thisWeek - lastWeek) / lastWeek * 100;
  if (percentChange == 0) return null;

  final isIncrease = percentChange > 0;
  final isFavorable = isIncrease == increaseIsGood;
  final color = isFavorable ? context.tokens.income : context.tokens.expense;
  final icon = isIncrease
      ? Icons.trending_up_outlined
      : Icons.trending_down_outlined;
  final sign = isIncrease ? '+' : '-';
  final percentText = '$sign${percentChange.abs().round()}%';

  return Semantics(
    label: '$percentText ${l10n.t('vsLastWeek')}',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          percentText,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// Compact "Workers this week" summary (v2 UI audit Task B2, Problem 6): the
/// dashboard should surface who actually worked, not just financial totals.
/// Derived from the existing `worker_entries` ledger — the same rolling
/// 7-day window used by the Weekly Summary cards above — so it needs no new
/// schema. Uses the same `Icons.engineering_outlined` glyph as the prominent
/// Workers resource card above for visual consistency.
class _WorkerAttendanceCard extends ConsumerWidget {
  const _WorkerAttendanceCard({
    required this.workspaceId,
    required this.locale,
  });

  final String workspaceId;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final summary = ref
        .watch(dashboardWorkerAttendanceProvider(workspaceId))
        .value;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final text = l10n.t(
      'workerAttendanceSummary',
      params: {
        'workers': Formatters.count(summary.workerCount, locale: locale),
        'manDays': Formatters.count(summary.manDays, locale: locale),
      },
    );

    return Semantics(
      label: text,
      child: BuildCard(
        key: const Key('qa_worker_attendance_summary'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.engineering_outlined,
              size: 20,
              color: context.tokens.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.tokens.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "Alerts" strip (v2 UI audit Task B5, Problem 16: the dashboard
/// should surface risk signals such as budget overruns and overdue
/// invoices). Presentation + light derivation only, over data already
/// fetched for the dashboard — no new Firestore queries.
///
/// Of the audit's five example warning types, only two are honestly
/// derivable from data that exists in this app today:
///  * "Budget exceeded" — a project where `totalExpenses > budgetLimit`,
///    the same budget fields [ProjectFinancialSection]'s progress bar
///    already uses (v2 UI audit Task A3).
///  * "Invoice overdue" — this app has no due-date concept on payments
///    (see `PaymentRecord`/`PaymentStatuses` — a payment only tracks
///    `amount` + `paymentStatus`, never a due date), so a fabricated
///    "overdue by N days" claim would not be honest. The closest genuine
///    signal is reused as-is from Task B3's
///    [dashboardOutstandingPaymentsProvider] (the live "unpaid payments"
///    total), surfaced here as an attention item rather than invented.
/// "Worker shortage" (no staffing-target data anywhere in this app),
/// "Delayed milestone" (no milestones subsystem — that's Phase C, net-new),
/// and "Upcoming payment" (same missing-due-date problem as overdue) are
/// skipped entirely rather than fabricated.
///
/// Renders nothing at all when there is nothing to flag — no empty "0
/// alerts" clutter.
class _AlertsCard extends ConsumerWidget {
  const _AlertsCard({
    required this.workspaceId,
    required this.projects,
    required this.currency,
    required this.locale,
  });

  final String workspaceId;
  final List<Project> projects;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;

    // Same budget-exceeded rule as ProjectFinancialSection's progress bar:
    // a project only counts once it has a real budget to exceed.
    final overBudgetProjects = projects
        .where(
          (project) =>
              project.budgetLimit != null &&
              project.budgetLimit! > 0 &&
              project.totalExpenses > project.budgetLimit!,
        )
        .toList(growable: false);

    // Reuse Task B3's provider outright rather than issuing a second
    // payments query — the outstanding total already reflects the
    // workspace's live unpaid-payments state.
    final outstanding =
        ref.watch(dashboardOutstandingPaymentsProvider(workspaceId)).value ?? 0;

    if (overBudgetProjects.isEmpty && outstanding <= 0) {
      return const SizedBox.shrink();
    }

    // A single over-budget project is named directly (specific and short
    // enough to read at a glance). Two or more are aggregated into one
    // count instead of rendering a wall of chips — the same "few vs many"
    // collapse-to-a-count idiom the Workers resource tile already uses.
    final budgetRows = overBudgetProjects.length == 1
        ? [
            _AlertRow(
              key: const Key('qa_dashboard_alert_project_over_budget'),
              icon: Icons.warning_amber_outlined,
              color: t.expense,
              text: l10n.t(
                'alertsProjectOverBudget',
                params: {'project': overBudgetProjects.first.name},
              ),
            ),
          ]
        : [
            _AlertRow(
              key: const Key('qa_dashboard_alert_projects_over_budget'),
              icon: Icons.warning_amber_outlined,
              color: t.expense,
              text: l10n.t(
                'alertsProjectsOverBudget',
                params: {'count': '${overBudgetProjects.length}'},
              ),
            ),
          ];

    return Container(
      key: const Key('qa_dashboard_alerts_card'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
        boxShadow: t.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, size: 16, color: t.warning),
              const SizedBox(width: 8),
              Text(
                l10n.t('alerts'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (overBudgetProjects.isNotEmpty)
            for (final row in budgetRows) ...[row, const SizedBox(height: 8)],
          if (outstanding > 0)
            _AlertRow(
              key: const Key('qa_dashboard_alert_unpaid_payments'),
              icon: Icons.receipt_long_outlined,
              color: t.warning,
              text: l10n.t(
                'alertsUnpaidPayments',
                params: {
                  'amount': Formatters.money(
                    outstanding,
                    currencyCode: currency,
                    locale: locale,
                  ),
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Single icon + text row within [_AlertsCard].
class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.icon,
    required this.color,
    required this.text,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.tokens.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact "Cash Collected / Outstanding Payments" card (v2 UI audit Task
/// B3, Construction-Specific Improvements: the dashboard should show what's
/// actually been collected vs. what remains outstanding, not just a single
/// net financial figure). Derived from the existing `payments` ledger's
/// `paymentStatus` field via two independently-shaped sources — see the doc
/// comment above [dashboardCashCollectedProvider] for exactly how
/// `paid`/`partial`/`unpaid` map to "collected" vs. "outstanding", and why
/// this card reads from a one-time fetch + a status-filtered live listener
/// instead of a single unbounded stream. Workspace-scoped like
/// [_WorkerAttendanceCard] above (shown regardless of the project filter),
/// since collection status reflects the whole ledger, not one project's
/// financial totals.
///
/// Outstanding uses `context.tokens.warning` rather than `context.tokens.
/// expense`: an unpaid invoice isn't a loss (it's not money that left the
/// business), it's an attention-needed/collections-risk signal — the same
/// semantic `warning` already carries for the sync-queue banner and worker
/// attendance icon above.
class _PaymentStatusCard extends ConsumerWidget {
  const _PaymentStatusCard({
    required this.workspaceId,
    required this.currency,
    required this.locale,
  });

  final String workspaceId;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final collectedAsync = ref.watch(
      dashboardCashCollectedProvider(workspaceId),
    );
    final outstandingAsync = ref.watch(
      dashboardOutstandingPaymentsProvider(workspaceId),
    );

    // Show a skeleton until BOTH sources have resolved at least once — same
    // "no janky partial card" convention as the rest of this screen (see
    // AsyncContentX.whenStale), just applied across two AsyncValues instead
    // of one. Once each has a first value, `hasValue` stays true through
    // subsequent reloads/refreshes/errors, so a transient refresh failure on
    // one side doesn't blank out already-shown figures.
    if (!collectedAsync.hasValue || !outstandingAsync.hasValue) {
      final firstLoadError =
          (!collectedAsync.hasValue && collectedAsync.hasError) ||
          (!outstandingAsync.hasValue && outstandingAsync.hasError);
      if (firstLoadError) {
        final error = collectedAsync.hasError
            ? collectedAsync.error!
            : outstandingAsync.error!;
        return AppRecoverableError(
          message: appErrorMessage(l10n, error),
          onRetry: () {
            ref.invalidate(dashboardCashCollectedProvider(workspaceId));
            ref.invalidate(dashboardOutstandingPaymentsProvider(workspaceId));
          },
        );
      }
      return AppLoadingSkeleton(
        lineCount: 2,
        semanticsLabel: l10n.t('loadingContent'),
      );
    }

    final collected = collectedAsync.value ?? 0;
    final outstanding = outstandingAsync.value ?? 0;

    return Row(
      key: const Key('qa_dashboard_payment_status_row'),
      children: [
        Expanded(
          child: MetricCard(
            key: const Key('qa_dashboard_cash_collected'),
            label: l10n.t('cashCollected'),
            value: Formatters.money(
              collected,
              currencyCode: currency,
              locale: locale,
            ),
            color: context.tokens.income,
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            key: const Key('qa_dashboard_outstanding_payments'),
            label: l10n.t('outstandingPayments'),
            value: Formatters.money(
              outstanding,
              currencyCode: currency,
              locale: locale,
            ),
            color: context.tokens.warning,
            icon: Icons.pending_actions_outlined,
          ),
        ),
      ],
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
