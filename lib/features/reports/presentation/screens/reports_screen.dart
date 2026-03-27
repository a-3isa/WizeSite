import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/cashflow_line_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/category_pie_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/monthly_flow_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/recent_expenses_table.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/recent_payments_table.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/worker_cost_table.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({this.projectId, super.key});

  final String? projectId;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    _updateProjectId();
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _updateProjectId();
    }
  }

  void _updateProjectId() {
    Future.microtask(() {
      if (mounted) {
        ref.read(reportProjectIdProvider.notifier).state = widget.projectId;
      }
    });
  }

  Future<void> _export({
    required AppLocalizations l10n,
    required Project project,
    required ReportMetrics metrics,
    required String currency,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    final document = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    pw.Widget sectionTitle(String text) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8, top: 18),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: fontBold,
            fontSize: 16,
            color: PdfColor.fromHex('#0F172A'),
          ),
        ),
      );
    }

    pw.Widget twoColumnTable(List<List<String>> rows) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1),
        },
        children: rows
            .map(
              (row) => pw.TableRow(
                children: row
                    .map(
                      (cell) => pw.Padding(
                        padding: const pw.EdgeInsets.all(10),
                        child: pw.Text(
                          cell,
                          style: pw.TextStyle(font: font, fontSize: 11),
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            l10n.t('buildozerFinancialReport'),
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 24,
              color: PdfColor.fromHex('#F59E0B'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            l10n.t('projectReport'),
            style: pw.TextStyle(font: font, fontSize: 12),
          ),
          pw.SizedBox(height: 12),
          twoColumnTable([
            [l10n.t('project'), project.name],
            [l10n.t('status'), l10n.projectStatusLabel(project.status)],
            [l10n.t('generated'), dateFormat.format(DateTime.now())],
          ]),
          sectionTitle(l10n.t('currentSnapshot')),
          twoColumnTable([
            [
              l10n.t('totalIncome'),
              '${metrics.totalIncome.toStringAsFixed(0)} $currency',
            ],
            [
              l10n.t('totalExpenses'),
              '${metrics.totalExpenses.toStringAsFixed(0)} $currency',
            ],
            [l10n.t('netProfit'), '${metrics.net.toStringAsFixed(0)} $currency'],
          ]),
          sectionTitle(l10n.t('expenseBreakdown')),
          twoColumnTable(
            metrics.categoryTotals.entries
                .map(
                  (entry) => [
                    l10n.expenseCategoryLabel(entry.key),
                    '${entry.value.toStringAsFixed(0)} $currency',
                  ],
                )
                .toList(),
          ),
          sectionTitle(l10n.t('monthlyCashFlow')),
          twoColumnTable(
            metrics.monthlyFlow
                .map(
                  (entry) => [
                    DateFormat('yyyy-MM').format(entry.month),
                    '${entry.income.toStringAsFixed(0)} / ${entry.expenses.toStringAsFixed(0)} $currency',
                  ],
                )
                .toList(),
          ),
          sectionTitle(l10n.t('topWorkers')),
          twoColumnTable(
            metrics.topWorkers.isEmpty
                ? [
                    [l10n.t('workerName'), l10n.t('noDataYet')],
                  ]
                : metrics.topWorkers
                    .map(
                      (worker) => [
                        worker.name,
                        '${worker.totalDays.toStringAsFixed(1)} d / ${worker.totalCost.toStringAsFixed(0)} $currency',
                      ],
                    )
                    .toList(),
          ),
          sectionTitle(l10n.t('recentExpenses')),
          twoColumnTable(
            metrics.recentExpenses.isEmpty
                ? [
                    [l10n.t('expenses'), l10n.t('noDataYet')],
                  ]
                : metrics.recentExpenses
                    .map(
                      (expense) => [
                        '${DateFormat('yyyy-MM-dd').format(expense.date)} ${l10n.expenseCategoryLabel(expense.category)}',
                        '${expense.amount.toStringAsFixed(0)} ${expense.currency}',
                      ],
                    )
                    .toList(),
          ),
          sectionTitle(l10n.t('recentPayments')),
          twoColumnTable(
            metrics.recentPayments.isEmpty
                ? [
                    [l10n.t('payments'), l10n.t('noDataYet')],
                  ]
                : metrics.recentPayments
                    .map(
                      (payment) => [
                        '${DateFormat('yyyy-MM-dd').format(payment.date)} ${l10n.paymentMethodLabel(payment.paymentMethod)}',
                        '${payment.amount.toStringAsFixed(0)} $currency',
                      ],
                    )
                    .toList(),
          ),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              l10n.t('generatedByBuildozer'),
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => document.save());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final currentProjectId = ref.watch(reportProjectIdProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);
    final metricsAsync = ref.watch(reportMetricsProvider);
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
            'EGP';
    final hasWorkspace = workspaceId != null;

    final categoryAsync = ref.watch(expensesByCategoryProvider);
    final flowAsync = ref.watch(monthlyFlowProvider);
    final workersAsync = ref.watch(topWorkersProvider);
    final expensesAsync = ref.watch(reportExpensesProvider);
    final paymentsAsync = ref.watch(reportPaymentsProvider);
    final fallbackRoute = widget.projectId == null
        ? AppRoutes.dashboard
        : AppRoutes.projectDetailPath(widget.projectId!);

    return AppBackScope(
      fallbackRoute: fallbackRoute,
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            AppBackButton(fallbackRoute: fallbackRoute),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.t('reports'),
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: AppColors.textDark,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasWorkspace && currentProjectId != null)
                        _ExportButton(
                          label: l10n.t('exportPdf'),
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final projects = ref.read(projectsProvider).valueOrNull;
                            final metrics = ref.read(reportMetricsProvider).valueOrNull;
                            final selectedProject = projects
                                ?.where((project) => project.id == currentProjectId)
                                .firstOrNull;
                            if (selectedProject == null || metrics == null) {
                              return;
                            }
                            await _export(
                              l10n: l10n,
                              project: selectedProject,
                              metrics: metrics,
                              currency: currency,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              if (hasWorkspace)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: projectsAsync.when(
                      data: (projects) {
                        if (projects.isEmpty) {
                          return Text(
                            l10n.t('noProjectsYet'),
                            style: const TextStyle(color: AppColors.textBody),
                          );
                        }

                        return DropdownButtonFormField<String>(
                          initialValue: projects.any((p) => p.id == currentProjectId)
                              ? currentProjectId
                              : null,
                          hint: Text(
                            l10n.t('selectProject'),
                            style: const TextStyle(color: AppColors.textBody),
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.borderGrey,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.borderGrey,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.constructionOrange,
                              ),
                            ),
                          ),
                          items: projects
                              .map(
                                (project) => DropdownMenuItem(
                                  value: project.id,
                                  child: Text(project.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            ref.read(reportProjectIdProvider.notifier).state = value;
                          },
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Text(error.toString()),
                    ),
                  ),
                ),
              if (currentProjectId == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.analytics_outlined,
                          size: 64,
                          color: AppColors.borderGrey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.t('selectProjectToViewReport'),
                          style: const TextStyle(
                            color: AppColors.textBody,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionHeader(title: l10n.t('currentSnapshot')),
                      const SizedBox(height: 12),
                      summaryAsync.when(
                        data: (summary) => summary.isEmpty
                            ? _EmptyCard(label: l10n.t('noWorkspaceSelected'))
                            : GridView.count(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: 1.4,
                                children: [
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
                                    value:
                                        '${(summary['net'] ?? 0).toStringAsFixed(0)} $currency',
                                    color: (summary['net'] ?? 0) >= 0
                                        ? AppColors.success
                                        : AppColors.danger,
                                    icon:
                                        Icons.account_balance_wallet_outlined,
                                  ),
                                ],
                              ),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 24),
                      categoryAsync.when(
                        data: (data) => CategoryPieChart(data: data),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      flowAsync.when(
                        data: (data) => MonthlyFlowChart(data: data),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      flowAsync.when(
                        data: (data) => CashflowLineChart(data: data),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 24),
                      expensesAsync.when(
                        data: (expenses) =>
                            RecentExpensesTable(expenses: expenses),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      paymentsAsync.when(
                        data: (payments) =>
                            RecentPaymentsTable(payments: payments),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      workersAsync.when(
                        data: (workers) => WorkerCostTable(workers: workers),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      metricsAsync.when(
                        data: (metrics) => metrics == null
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceGrey,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.borderGrey,
                                  ),
                                ),
                                child: Text(
                                  '${metrics.projectName} • ${l10n.projectStatusLabel(metrics.status)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.textBody),
                                ),
                              ),
                        error: (error, _) => _ErrorCard(message: error.toString()),
                        loading: () => const SizedBox.shrink(),
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
                              const Icon(
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
                                      'limit':
                                          '${usage.limits.expensesPerMonth}',
                                    },
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textBody),
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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textBody,
            letterSpacing: 0.5,
          ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.constructionOrange.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.picture_as_pdf_outlined,
                size: 18,
                color: AppColors.constructionOrange,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.constructionOrange,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.label});

  final String label;

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
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textBody),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    );
  }
}
