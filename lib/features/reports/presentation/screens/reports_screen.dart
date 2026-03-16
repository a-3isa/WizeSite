import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _export({
    required AppLocalizations l10n,
    required String workspaceId,
    required Map<String, num> summary,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              l10n.t('buildozerFinancialReport'),
              style: pw.TextStyle(fontSize: 22),
            ),
            pw.SizedBox(height: 8),
            pw.Text('${l10n.t('workspace')}: $workspaceId'),
            pw.Text('${l10n.t('generated')}: ${DateTime.now().toIso8601String()}'),
            pw.SizedBox(height: 20),
            pw.Text(
              l10n.t(
                'totalProjects',
                params: {'value': '${(summary['totalProjects'] ?? 0).toInt()}'},
              ),
            ),
            pw.Text(
              l10n.t(
                'activeProjectsCount',
                params: {
                  'value': '${(summary['activeProjects'] ?? 0).toInt()}',
                },
              ),
            ),
            pw.Text(
              l10n.t(
                'totalExpensesLabel',
                params: {
                  'value':
                      (summary['totalExpenses'] ?? 0).toStringAsFixed(0),
                },
              ),
            ),
            pw.Text(
              l10n.t(
                'totalIncomeLabel',
                params: {'value': (summary['totalIncome'] ?? 0).toStringAsFixed(0)},
              ),
            ),
            pw.Text(
              l10n.t(
                'netProfitLoss',
                params: {'value': (summary['net'] ?? 0).toStringAsFixed(0)},
              ),
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => document.save());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final summaryAsync = workspaceId == null
        ? const AsyncValue.data(<String, num>{})
        : ref.watch(dashboardSummaryProvider(workspaceId));
    final hasWorkspace = workspaceId != null;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  l10n.t('reports'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.textDark,
                      ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  _ReportCard(
                    icon: Icons.picture_as_pdf_outlined,
                    title: l10n.t('projectFinancialReport'),
                    subtitle: l10n.t('projectFinancialReportSubtitle'),
                    color: AppColors.constructionOrange,
                    enabled: hasWorkspace,
                    onTap: hasWorkspace
                        ? () async {
                            HapticFeedback.lightImpact();
                            final summary = await ref.read(
                              dashboardSummaryProvider(workspaceId).future,
                            );
                            if (context.mounted) {
                              await _export(
                                l10n: l10n,
                                workspaceId: workspaceId,
                                summary: summary,
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _ReportCard(
                    icon: Icons.table_chart_outlined,
                    title: l10n.t('expenseReport'),
                    subtitle: l10n.t('expenseReportSubtitle'),
                    color: AppColors.danger,
                    enabled: false,
                    onTap: null,
                  ),
                  const SizedBox(height: 8),
                  _ReportCard(
                    icon: Icons.groups_outlined,
                    title: l10n.t('workerCostReport'),
                    subtitle: l10n.t('workerCostReportSubtitle'),
                    color: AppColors.constructionOrange,
                    enabled: false,
                    onTap: null,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.t('currentSnapshot'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textBody,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const SizedBox(height: 12),
                  summaryAsync.when(
                    data: (summary) => summary.isEmpty
                        ? _EmptySnapshotCard(l10n: l10n)
                        : GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 1.4,
                            children: [
                              MetricCard(
                                label: l10n.t('activeProjects'),
                                value:
                                    '${summary['activeProjects']?.toInt() ?? 0}',
                                color: AppColors.constructionOrange,
                                icon: Icons.work_outline,
                              ),
                              MetricCard(
                                label: l10n.t('totalExpenses'),
                                value:
                                    '${summary['totalExpenses']?.toStringAsFixed(0) ?? 0}',
                                color: AppColors.danger,
                                icon: Icons.trending_down,
                              ),
                              MetricCard(
                                label: l10n.t('totalIncome'),
                                value:
                                    '${summary['totalIncome']?.toStringAsFixed(0) ?? 0}',
                                color: AppColors.success,
                                icon: Icons.trending_up,
                              ),
                              MetricCard(
                                label: l10n.t('netProfit'),
                                value:
                                    '${(summary['net'] ?? 0).toStringAsFixed(0)} EGP',
                                color: (summary['net'] ?? 0) >= 0
                                    ? AppColors.success
                                    : AppColors.danger,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            ],
                          ),
                    error: (e, _) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.danger),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              e.toString(),
                              style: TextStyle(color: AppColors.danger),
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
                  usageAsync.when(
                    data: (usage) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceGrey,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderGrey),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.pie_chart_outline,
                            size: 20,
                            color: AppColors.textBody,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.t(
                                'usagePeriod',
                                params: {
                                  'period': usage.periodKey,
                                  'count': '${usage.expensesCount}',
                                  'limit': '${usage.limits.expensesPerMonth}',
                                },
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textBody,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySnapshotCard extends StatelessWidget {
  const _EmptySnapshotCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textBody,
              ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : AppColors.textBody;
    final opacity = enabled ? 1.0 : 0.6;

    return Opacity(
      opacity: opacity,
      child: Material(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: effectiveColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textBody,
                                ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textBody.withValues(alpha: 0.6),
                    size: 24,
                  )
                else
                  Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: AppColors.textBody.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
