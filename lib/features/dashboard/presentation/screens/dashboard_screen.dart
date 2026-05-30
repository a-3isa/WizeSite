import 'dart:async';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_limits.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/offline_queue_coordinator.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
import 'package:go_router/go_router.dart';
import 'package:buildtrack_app/core/widgets/usage_card.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final subscriptionAsync = ref.watch(currentSubscriptionStreamProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final pendingSyncCount = ref.watch(offlinePendingCountProvider);
    final deadLetterCount = ref.watch(offlineDeadLetterCountProvider);
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    final locale = Localizations.localeOf(context).languageCode;
    final summaryAsync = workspaceId == null
        ? const AsyncValue.data(<String, num>{})
        : ref.watch(dashboardSummaryProvider(workspaceId));
    final weeklySummaryAsync = workspaceId == null
        ? const AsyncValue.data(<String, num>{})
        : ref.watch(dashboardWeeklySummaryProvider(workspaceId));
    final weeklyInsightsAsync = workspaceId == null
        ? AsyncValue.data(
            DashboardWeeklyInsights(
              topEntity: 'Unassigned',
              topCategory: 'Unassigned',
              laborTotal: 0,
              equipmentTotal: 0,
              paymentSummary: {},
              recentTransactions: [],
            ),
          )
        : ref.watch(dashboardWeeklyInsightsProvider(workspaceId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('home')),
        actions: [
          IconButton(
            key: const Key('qa_dashboard_settings'),
            onPressed: () {
              ref.read(appPrefetcherProvider).warmSettings();
              context.push(AppRoutes.settings);
            },
            icon: const Icon(Icons.settings_outlined),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceSolid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.borderGrey),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
          child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            if (deadLetterCount > 0) ...[
              _QueueStatusCard(
                color: AppColors.danger,
                icon: Icons.sync_problem_outlined,
                message: l10n.t(
                  'offlineSyncFailed',
                  params: {'count': '$deadLetterCount'},
                ),
                actionLabel: l10n.t('retry'),
                onAction: () => _retryOfflineWork(ref),
              ),
              const SizedBox(height: 12),
            ] else if (pendingSyncCount > 0) ...[
              _QueueStatusCard(
                color: AppColors.warning,
                icon: Icons.cloud_upload_outlined,
                message: l10n.t(
                  'offlineSyncPending',
                  params: {'count': '$pendingSyncCount'},
                ),
                actionLabel: l10n.t('retry'),
                onAction: () => _retryOfflineWork(ref),
              ),
              const SizedBox(height: 12),
            ],
            SectionHeader(title: l10n.t('overview')),
            const SizedBox(height: 16),
            summaryAsync.when(
              data: (summary) {
                if (summary.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSolid,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderGrey),
                    ),
                    child: Center(
                      child: Text(
                        l10n.t('noWorkspaceSelected'),
                        style: TextStyle(color: AppColors.textBody),
                      ),
                    ),
                  );
                }
                final net = summary['net'] ?? 0;
                return GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.4,
                  children: [
                    MetricCard(
                      label: l10n.t('activeProjects'),
                      value: '${summary['activeProjects']?.toInt() ?? 0}',
                      color: AppColors.constructionOrange,
                      icon: Icons.work_outline,
                    ),
                    MetricCard(
                      label: l10n.t('totalExpenses'),
                      value: Formatters.money(
                        summary['totalExpenses'] ?? 0,
                        currencyCode: currency,
                        locale: locale,
                      ),
                      color: AppColors.danger,
                      icon: Icons.trending_down,
                    ),
                    MetricCard(
                      label: l10n.t('totalIncome'),
                      value: Formatters.money(
                        summary['totalIncome'] ?? 0,
                        currencyCode: currency,
                        locale: locale,
                      ),
                      color: AppColors.success,
                      icon: Icons.trending_up,
                    ),
                    MetricCard(
                      label: l10n.t('netProfit'),
                      value: Formatters.money(
                        net,
                        currencyCode: currency,
                        locale: locale,
                      ),
                      color: net >= 0 ? AppColors.success : AppColors.danger,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                );
              },
              error: (e, s) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        e.toString(),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
              loading: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            weeklySummaryAsync.when(
              data: (weeklySummary) {
                if (weeklySummary.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(title: l10n.t('weeklySummary')),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.4,
                      children: [
                        MetricCard(
                          label: l10n.t('totalExpenses'),
                          value: Formatters.money(
                            weeklySummary['weeklyExpenses'] ?? 0,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          color: AppColors.danger,
                          icon: Icons.trending_down,
                        ),
                        MetricCard(
                          label: l10n.t('totalIncome'),
                          value: Formatters.money(
                            weeklySummary['weeklyIncome'] ?? 0,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          color: AppColors.success,
                          icon: Icons.trending_up,
                        ),
                        MetricCard(
                          label: l10n.t('netProfit'),
                          value: Formatters.money(
                            weeklySummary['weeklyNet'] ?? 0,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          color: (weeklySummary['weeklyNet'] ?? 0) >= 0
                              ? AppColors.success
                              : AppColors.danger,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
            ),
            weeklyInsightsAsync.when(
              data: (insights) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: l10n.t('weeklyInsights')),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.4,
                    children: [
                      MetricCard(
                        label: l10n.t('topEntity'),
                        value: insights.topEntity,
                        color: AppColors.surfaceSolid,
                        icon: Icons.business_outlined,
                      ),
                      MetricCard(
                        label: l10n.t('topCategory'),
                        value: insights.topCategory,
                        color: AppColors.surfaceSolid,
                        icon: Icons.category_outlined,
                      ),
                      MetricCard(
                        label: l10n.t('laborExpenses'),
                        value: Formatters.money(
                          insights.laborTotal,
                          currencyCode: currency,
                          locale: locale,
                        ),
                        color: AppColors.warning,
                        icon: Icons.construction_outlined,
                      ),
                      MetricCard(
                        label: l10n.t('equipmentExpenses'),
                        value: Formatters.money(
                          insights.equipmentTotal,
                          currencyCode: currency,
                          locale: locale,
                        ),
                        color: AppColors.constructionOrange,
                        icon: Icons.engineering_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (insights.paymentSummary.isNotEmpty) ...[
                    SectionHeader(title: l10n.t('paymentBreakdown')),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: insights.paymentSummary.entries
                          .map(
                            (entry) => MetricCard(
                              label: entry.key,
                              value: Formatters.money(
                                entry.value,
                                currencyCode: currency,
                                locale: locale,
                              ),
                              color: AppColors.surfaceSolid,
                              icon: Icons.payment_outlined,
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (insights.recentTransactions.isNotEmpty) ...[
                    SectionHeader(title: l10n.t('recentTransactions')),
                    const SizedBox(height: 12),
                    Column(
                      children: insights.recentTransactions.map((transaction) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            transaction.type == 'payment'
                                ? Icons.payments_outlined
                                : Icons.receipt_long_outlined,
                            color: AppColors.textBody,
                          ),
                          title: Text(transaction.title),
                          subtitle: Text(
                            Formatters.date(transaction.date, locale: locale),
                          ),
                          trailing: Text(
                            Formatters.money(
                              transaction.amount,
                              currencyCode: currency,
                              locale: locale,
                            ),
                            style: TextStyle(
                              color: transaction.type == 'payment'
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
            ),
            SectionHeader(title: l10n.t('quickActions')),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    qaKey: const Key('qa_add_expense'),
                    icon: Icons.receipt_long_outlined,
                    label: l10n.t('addExpense'),
                    color: AppColors.danger,
                    onTap: () => _onQuotaAction(
                      context,
                      ref,
                      LimitType.expensesPerMonth,
                      AppRoutes.addExpense,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    qaKey: const Key('qa_add_payment'),
                    icon: Icons.payments_outlined,
                    label: l10n.t('addPayment'),
                    color: AppColors.success,
                    onTap: () => _onQuotaAction(
                      context,
                      ref,
                      LimitType.paymentsPerMonth,
                      AppRoutes.addPayment,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    qaKey: const Key('qa_workers_list'),
                    icon: Icons.engineering_outlined,
                    label: l10n.t('workers'),
                    color: AppColors.warning,
                    onTap: () {
                      ref.read(appPrefetcherProvider).warmProjects();
                      context.push(AppRoutes.workers);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    qaKey: const Key('qa_create_project'),
                    icon: Icons.dashboard_customize_outlined,
                    label: l10n.t('createProject'),
                    color: AppColors.constructionOrange,
                    onTap: () => _onQuotaAction(
                      context,
                      ref,
                      LimitType.activeProjects,
                      AppRoutes.createProject,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            usageAsync.when(
              data: (usage) => UsageCard(usage: usage),
              error: (e, s) => const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            subscriptionAsync.when(
              data: (sub) => sub.tier == PlanTier.free
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.constructionOrange,
                            Color(0xFFFF9100),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.constructionOrange.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () =>
                              context.push(AppRoutes.subscriptionPlans),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.workspace_premium,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.t('upgradeToPro'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        l10n.t('unlockHigherLimits'),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _onQuotaAction(
    BuildContext context,
    WidgetRef ref,
    LimitType type,
    String route,
  ) {
    ref.read(appPrefetcherProvider).warmAddEntry();
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        AppLimits.usageLimitsDisabled) {
      context.push(route);
      return;
    }

    // Use already-loaded subscription data — no network call needed
    final sub = ref.read(currentSubscriptionStreamProvider).value;
    if (sub != null && sub.isActiveOrTrial && sub.tier == PlanTier.pro) {
      context.push(route);
      return;
    }

    // Use already-loaded usage snapshot — no network call needed
    final usage = ref.read(currentUsageProvider).value;
    if (usage == null) {
      context.push(route); // data not yet loaded, navigate optimistically
      return;
    }

    final current = usage.currentByType(type);
    final max = usage.maxByType(type);
    if (current + 1 > max) {
      final limit = Uri.encodeComponent(type.name);
      context.push('${AppRoutes.subscriptionLimit}?limit=$limit');
      return;
    }
    context.push(route);
  }

  void _retryOfflineWork(WidgetRef ref) {
    final coordinator = ref.read(offlineQueueCoordinatorProvider);
    unawaited(coordinator.refreshCounts());
    unawaited(coordinator.drainNow());
  }
}

class _QueueStatusCard extends StatelessWidget {
  const _QueueStatusCard({
    required this.color,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    this.qaKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Key? qaKey;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: qaKey,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceSolid,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderGrey),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.78)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
