import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/projects/data/project_repository.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/widgets/project_details_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
    final locale = Localizations.localeOf(context).languageCode;

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
                _ProjectFinancialHero(
                  project: project,
                  currency: currency,
                  locale: locale,
                  l10n: l10n,
                ),
                const SizedBox(height: 24),
                SectionHeader(title: l10n.t('recentTransactions')),
                const SizedBox(height: 12),
                _ProjectRecentTransactions(
                  workspaceId: project.workspaceId,
                  projectId: project.id,
                  currency: currency,
                  locale: locale,
                  l10n: l10n,
                ),
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
                                        : context.tokens.textMuted,
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

/// Hero net figure + funds-in/spent split for a single project, followed by a
/// budget-used progress bar (falls back to contract value when no explicit
/// budget limit is set). Mirrors the dashboard's project-scoped financial
/// section so the visual language matches across screens.
class _ProjectFinancialHero extends StatelessWidget {
  const _ProjectFinancialHero({
    required this.project,
    required this.currency,
    required this.locale,
    required this.l10n,
  });

  final Project project;
  final String currency;
  final String locale;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final numberFormat = NumberFormat.decimalPattern(locale);
    final isProfit = project.netProfit >= 0;
    final netText =
        '${isProfit ? '' : '−'}${numberFormat.format(project.netProfit.abs())}';
    final budgetBase = (project.budgetLimit != null && project.budgetLimit! > 0)
        ? project.budgetLimit!
        : project.contractValue;
    final hasBudget = budgetBase > 0;
    final ratio = hasBudget
        ? (project.totalExpenses / budgetBase).clamp(0.0, 1.0)
        : 0.0;
    final overBudget = hasBudget && project.totalExpenses > budgetBase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          BuildCard(
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
                        color: t.text,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '${Formatters.money(project.totalExpenses, currencyCode: currency, locale: locale)} / '
                        '${Formatters.money(budgetBase, currencyCode: currency, locale: locale)}',
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio.toDouble(),
                    minHeight: 8,
                    backgroundColor: t.surface3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      overBudget ? t.expense : t.accent,
                    ),
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
                    color: overBudget ? t.expense : t.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Recent expenses/payments for this project, newest first, rendered as
/// [MoneyRow]s inside a surface card. Reuses the existing dashboard
/// [projectRecentTransactionsProvider] (unchanged) so the same data powers
/// both the dashboard's project view and this detail screen.
class _ProjectRecentTransactions extends ConsumerWidget {
  const _ProjectRecentTransactions({
    required this.workspaceId,
    required this.projectId,
    required this.currency,
    required this.locale,
    required this.l10n,
  });

  final String workspaceId;
  final String projectId;
  final String currency;
  final String locale;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workspaceId.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long_outlined,
        message: l10n.t('noDataYet'),
      );
    }

    final recentAsync = ref.watch(
      projectRecentTransactionsProvider((
        workspaceId: workspaceId,
        projectId: projectId,
      )),
    );

    return recentAsync.when(
      data: (items) => items.isEmpty
          ? AppEmptyState(
              key: const Key('qa_project_detail_recent_empty'),
              icon: Icons.receipt_long_outlined,
              message: l10n.t('noDataYet'),
            )
          : BuildCard(
              key: const Key('qa_project_detail_recent'),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: MoneyRow(
                        title: item.title.isNotEmpty ? item.title : '—',
                        amount: NumberFormat.decimalPattern(
                          locale,
                        ).format(item.amount.abs()),
                        currency: currency,
                        kind: item.type == 'payment'
                            ? MoneyKind.income
                            : MoneyKind.expense,
                        showDivider: item != items.last,
                      ),
                    ),
                ],
              ),
            ),
      loading: () => AppLoadingSkeleton(semanticsLabel: l10n.t('loadingContent')),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
