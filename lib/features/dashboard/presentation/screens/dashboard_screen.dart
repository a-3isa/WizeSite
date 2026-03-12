import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/core/widgets/usage_card.dart';
import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final dashboardSummaryProvider =
    FutureProvider.family<Map<String, num>, String>((ref, workspaceId) async {
      final firestore = ref.watch(firestoreProvider);

      final projectsCount = await firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('isArchived', isEqualTo: false)
          .count()
          .get();
      final activeProjectsCount = await firestore
          .collection('projects')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('status', isEqualTo: 'active')
          .where('isArchived', isEqualTo: false)
          .count()
          .get();

      final expensesSnap = await firestore
          .collection('expenses')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('isArchived', isEqualTo: false)
          .limit(500)
          .get();
      final paymentsSnap = await firestore
          .collection('payments')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('isArchived', isEqualTo: false)
          .limit(500)
          .get();
      final workerEntriesSnap = await firestore
          .collection('worker_entries')
          .where('workspaceId', isEqualTo: workspaceId)
          .where('isArchived', isEqualTo: false)
          .limit(500)
          .get();

      final expenses = expensesSnap.docs.fold<num>(
        0,
        (total, doc) => total + ((doc.data()['amount'] as num?) ?? 0),
      );
      final labor = workerEntriesSnap.docs.fold<num>(
        0,
        (total, doc) => total + ((doc.data()['totalCost'] as num?) ?? 0),
      );
      final income = paymentsSnap.docs.fold<num>(
        0,
        (total, doc) => total + ((doc.data()['amount'] as num?) ?? 0),
      );

      final totalExpenses = expenses + labor;
      final net = income - totalExpenses;

      return {
        'totalProjects': projectsCount.count ?? 0,
        'activeProjects': activeProjectsCount.count ?? 0,
        'totalExpenses': totalExpenses,
        'totalIncome': income,
        'net': net,
      };
    });

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final subscriptionAsync = ref.watch(currentSubscriptionProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final summaryAsync = workspaceId == null
        ? const AsyncValue.data(<String, num>{})
        : ref.watch(dashboardSummaryProvider(workspaceId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('home')),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.notifications),
            icon: const Icon(Icons.notifications_outlined),
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
            Text(
              "Overview",
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
                    child: const Center(
                      child: Text(
                        'No workspace selected yet.',
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
                    ),
                    MetricCard(
                      label: 'Total Expenses',
                      value:
                          '${summary['totalExpenses']?.toStringAsFixed(0) ?? 0}',
                      color: AppColors.danger,
                    ),
                    MetricCard(
                      label: 'Total Income',
                      value:
                          '${summary['totalIncome']?.toStringAsFixed(0) ?? 0}',
                      color: AppColors.success,
                    ),
                    MetricCard(
                      label: 'Net Profit',
                      value: '${net.toStringAsFixed(0)} EGP',
                      color: net >= 0 ? AppColors.success : AppColors.danger,
                    ),
                  ],
                );
              },
              error: (error, _) => Text(
                error.toString(),
                style: const TextStyle(color: AppColors.danger),
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
              'Quick Actions',
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
              error: (error, _) => Text(
                error.toString(),
                style: const TextStyle(color: AppColors.danger),
              ),
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
                                      const Text(
                                        'Unlock higher limits and team scaling',
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

  Future<void> _onQuotaAction(
    BuildContext context,
    WidgetRef ref,
    LimitType type,
    String route,
  ) async {
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (workspaceId == null || workspaceId.isEmpty) {
      context.push(route);
      return;
    }

    final guard = ref.read(entitlementGuardProvider);
    final result = await guard.checkQuota(
      workspaceId: workspaceId,
      type: type,
      delta: 1,
    );
    if (!result.allowed) {
      final limit = Uri.encodeComponent(type.name);
      if (context.mounted) {
        context.push('${AppRoutes.subscriptionLimit}?limit=$limit');
      }
      return;
    }
    if (context.mounted) {
      context.push(route);
    }
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
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
