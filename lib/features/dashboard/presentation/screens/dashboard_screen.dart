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
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            summaryAsync.when(
              data: (summary) {
                if (summary.isEmpty) {
                  return const Text('No workspace selected yet.');
                }
                final net = summary['net'] ?? 0;
                return GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    MetricCard(
                      label: 'Total Projects',
                      value: '${summary['totalProjects']?.toInt() ?? 0}',
                    ),
                    MetricCard(
                      label: l10n.t('activeProjects'),
                      value: '${summary['activeProjects']?.toInt() ?? 0}',
                    ),
                    MetricCard(
                      label: 'Total Expenses',
                      value:
                          '${summary['totalExpenses']?.toStringAsFixed(0) ?? 0} EGP',
                      color: AppColors.danger,
                    ),
                    MetricCard(
                      label: 'Total Income',
                      value:
                          '${summary['totalIncome']?.toStringAsFixed(0) ?? 0} EGP',
                      color: AppColors.success,
                    ),
                    MetricCard(
                      label: 'Net Profit/Loss',
                      value: '${net.toStringAsFixed(0)} EGP',
                      color: net >= 0 ? AppColors.success : AppColors.danger,
                    ),
                  ],
                );
              },
              error: (error, _) => Text(error.toString()),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 16),
            usageAsync.when(
              data: (usage) => UsageCard(usage: usage),
              error: (error, _) => Text(error.toString()),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 12),
            subscriptionAsync.when(
              data: (sub) => sub.tier == PlanTier.free
                  ? Card(
                      child: ListTile(
                        leading: const Icon(Icons.workspace_premium),
                        title: Text(l10n.t('upgradeToPro')),
                        subtitle: const Text(
                          'Unlock higher limits and team scaling',
                        ),
                        trailing: FilledButton(
                          onPressed: () =>
                              context.push(AppRoutes.subscriptionPlans),
                          child: const Text('Upgrade'),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Text(
              'Quick Actions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickActionChip(
                  key: const Key('qa_add_expense'),
                  label: l10n.t('addExpense'),
                  onTap: () => _onQuotaAction(
                    context,
                    ref,
                    LimitType.expensesPerMonth,
                    AppRoutes.addExpense,
                  ),
                ),
                _QuickActionChip(
                  key: const Key('qa_add_payment'),
                  label: l10n.t('addPayment'),
                  onTap: () => _onQuotaAction(
                    context,
                    ref,
                    LimitType.paymentsPerMonth,
                    AppRoutes.addPayment,
                  ),
                ),
                _QuickActionChip(
                  key: const Key('qa_add_worker_entry'),
                  label: l10n.t('addWorkerEntry'),
                  onTap: () => _onQuotaAction(
                    context,
                    ref,
                    LimitType.workerEntriesPerMonth,
                    AppRoutes.workerEntry.replaceFirst(':id', 'new'),
                  ),
                ),
                _QuickActionChip(
                  key: const Key('qa_create_project'),
                  label: l10n.t('createProject'),
                  onTap: () => _onQuotaAction(
                    context,
                    ref,
                    LimitType.activeProjects,
                    AppRoutes.createProject,
                  ),
                ),
              ],
            ),
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

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.add, size: 18),
      onPressed: onTap,
    );
  }
}
