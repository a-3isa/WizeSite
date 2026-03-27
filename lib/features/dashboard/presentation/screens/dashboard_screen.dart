import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/offline_queue_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
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
    final summaryAsync = workspaceId == null
        ? const AsyncValue.data(<String, num>{})
        : ref.watch(dashboardSummaryProvider(workspaceId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('home')),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.settings),
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
              ),
              const SizedBox(height: 12),
            ],
            Text(
              l10n.t('overview'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
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
                      value:
                          '${summary['totalExpenses']?.toStringAsFixed(0) ?? 0} $currency',
                      color: AppColors.danger,
                      icon: Icons.trending_down,
                    ),
                    MetricCard(
                      label: l10n.t('totalIncome'),
                      value:
                          '${summary['totalIncome']?.toStringAsFixed(0) ?? 0} $currency',
                      color: AppColors.success,
                      icon: Icons.trending_up,
                    ),
                    MetricCard(
                      label: l10n.t('netProfit'),
                      value: '${net.toStringAsFixed(0)} $currency',
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
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.danger,
                    ),
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
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.t('quickActions'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
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
                    qaKey: const Key('qa_add_worker_entry'),
                    icon: Icons.engineering_outlined,
                    label: l10n.t('addWorkerEntry'),
                    color: AppColors.warning,
                    onTap: () => _onQuotaAction(
                      context,
                      ref,
                      LimitType.workerEntriesPerMonth,
                      AppRoutes.workerEntry.replaceFirst(':id', 'new'),
                    ),
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
              loading: () => const Center(child: CircularProgressIndicator()),
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
              error: (_, _) => const SizedBox.shrink(),
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
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      context.go(route);
      return;
    }

    // Use already-loaded subscription data — no network call needed
    final sub = ref.read(currentSubscriptionStreamProvider).value;
    if (sub != null && sub.isActiveOrTrial && sub.tier == PlanTier.pro) {
      context.go(route);
      return;
    }

    // Use already-loaded usage snapshot — no network call needed
    final usage = ref.read(currentUsageProvider).value;
    if (usage == null) {
      context.go(route); // data not yet loaded, navigate optimistically
      return;
    }

    final current = usage.currentByType(type);
    final max = usage.maxByType(type);
    if (current + 1 > max) {
      final limit = Uri.encodeComponent(type.name);
      context.push('${AppRoutes.subscriptionLimit}?limit=$limit');
      return;
    }
    context.go(route);
  }
}

class _QueueStatusCard extends StatelessWidget {
  const _QueueStatusCard({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

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
      color: AppColors.surfaceSolid,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderGrey),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
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
