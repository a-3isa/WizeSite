import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/cashflow_line_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/category_pie_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/monthly_flow_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/recent_expenses_table.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/recent_payments_table.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/worker_cost_table.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    try {
      final exporter = const ReportPdfExporter();
      final documentBytes = await exporter.buildProjectReportPdf(
        l10n: l10n,
        project: project,
        metrics: metrics,
        currency: currency,
      );
      await Printing.layoutPdf(onLayout: (_) async => documentBytes);
    } catch (error) {
      _showExportError(l10n, error);
    }
  }

  Future<void> _exportWeekly({
    required AppLocalizations l10n,
    required DashboardWeeklyInsights insights,
    required String currency,
  }) async {
    try {
      final exporter = const ReportPdfExporter();
      final documentBytes = await exporter.buildWeeklyInsightsReportPdf(
        l10n: l10n,
        insights: insights,
        currency: currency,
      );
      await Printing.layoutPdf(onLayout: (_) async => documentBytes);
    } catch (error) {
      _showExportError(l10n, error);
    }
  }

  Future<void> _exportCombined({
    required AppLocalizations l10n,
    required Project project,
    required ReportMetrics metrics,
    required DashboardWeeklyInsights insights,
    required String currency,
  }) async {
    try {
      final exporter = const ReportPdfExporter();
      final documentBytes = await exporter.buildCombinedReportPdf(
        l10n: l10n,
        project: project,
        metrics: metrics,
        insights: insights,
        currency: currency,
      );
      await Printing.layoutPdf(onLayout: (_) async => documentBytes);
    } catch (error) {
      _showExportError(l10n, error);
    }
  }

  Future<void> _openCustomReportBuilder({
    required AppLocalizations l10n,
    required Project project,
    required DashboardWeeklyInsights insights,
    required String currency,
  }) async {
    var includeExpenses = true;
    var includePayments = true;
    var includeWeekly = true;
    var includeEntities = true;
    var includeDaily = true;
    DateTime? startDate;
    DateTime? endDate;

    String dateLabel(DateTime? value) => value == null
        ? l10n.t('dateRange')
        : value.toIso8601String().split('T').first;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('buildCustomReport'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: startDate ?? DateTime.now(),
                            );
                            if (picked != null) {
                              setSheetState(() => startDate = picked);
                            }
                          },
                          child: Text(dateLabel(startDate)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: endDate ?? DateTime.now(),
                            );
                            if (picked != null) {
                              setSheetState(() => endDate = picked);
                            }
                          },
                          child: Text(dateLabel(endDate)),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeExpenses,
                    onChanged: (value) =>
                        setSheetState(() => includeExpenses = value ?? true),
                    title: Text(l10n.t('exportExpenses')),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includePayments,
                    onChanged: (value) =>
                        setSheetState(() => includePayments = value ?? true),
                    title: Text(l10n.t('exportPayments')),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeWeekly,
                    onChanged: (value) =>
                        setSheetState(() => includeWeekly = value ?? true),
                    title: Text(l10n.t('exportWeeklyReport')),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeEntities,
                    onChanged: (value) =>
                        setSheetState(() => includeEntities = value ?? true),
                    title: Text(l10n.t('entitySummary')),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeDaily,
                    onChanged: (value) =>
                        setSheetState(() => includeDaily = value ?? true),
                    title: Text(l10n.t('dailyBreakdown')),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _generateCustomReport(
                          l10n: l10n,
                          project: project,
                          insights: insights,
                          currency: currency,
                          startDate: startDate,
                          endDate: endDate,
                          includeExpenses: includeExpenses,
                          includePayments: includePayments,
                          includeWeekly: includeWeekly,
                          includeEntities: includeEntities,
                          includeDaily: includeDaily,
                        );
                      },
                      child: Text(l10n.t('exportPdf')),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generateCustomReport({
    required AppLocalizations l10n,
    required Project project,
    required DashboardWeeklyInsights insights,
    required String currency,
    required DateTime? startDate,
    required DateTime? endDate,
    required bool includeExpenses,
    required bool includePayments,
    required bool includeWeekly,
    required bool includeEntities,
    required bool includeDaily,
  }) async {
    try {
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      final entitySummaries = workspaceId == null
          ? const <EntitySummary>[]
          : (ref.read(entityAggregationsProvider(workspaceId)).valueOrNull ??
                const <EntitySummary>[]);

      // The daily breakdown is derived from expenses, so fetch them whenever
      // either the expenses section or the daily section is requested.
      final effectiveStartDate =
          startDate ?? DateTime(DateTime.now().year, DateTime.now().month);
      final effectiveEndDate = endDate ?? DateTime.now();
      final inclusiveEndDate = DateTime(
        effectiveEndDate.year,
        effectiveEndDate.month,
        effectiveEndDate.day,
        23,
        59,
        59,
        999,
      );
      var expenses = const <Expense>[];
      if ((includeExpenses || includeDaily) && workspaceId != null) {
        final page = await ref
            .read(expenseRepositoryProvider)
            .fetchExpensesPage(
              workspaceId,
              projectId: project.id,
              startDate: effectiveStartDate,
              endDate: inclusiveEndDate,
              pageSize: 500,
            );
        expenses = page.items;
      }

      var payments = const <PaymentRecord>[];
      if (includePayments && workspaceId != null) {
        final page = await ref
            .read(paymentRepositoryProvider)
            .fetchPaymentsPage(
              workspaceId,
              projectId: project.id,
              startDate: effectiveStartDate,
              endDate: inclusiveEndDate,
              pageSize: 500,
            );
        payments = page.items;
      }

      final exporter = const ReportPdfExporter();
      final documentBytes = await exporter.buildCustomReportPdf(
        l10n: l10n,
        project: project,
        expenses: expenses,
        payments: payments,
        insights: insights,
        entitySummaries: entitySummaries,
        currency: currency,
        startDate: effectiveStartDate,
        endDate: inclusiveEndDate,
        includeExpenses: includeExpenses,
        includePayments: includePayments,
        includeWeekly: includeWeekly,
        includeEntities: includeEntities,
        includeDaily: includeDaily,
      );
      await Printing.layoutPdf(onLayout: (_) async => documentBytes);
    } catch (error) {
      _showExportError(l10n, error);
    }
  }

  void _showExportError(AppLocalizations l10n, Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.t('reportExportFailed'))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final currentProjectId = ref.watch(reportProjectIdProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final currency =
        ref.watch(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    final hasWorkspace = workspaceId != null;
    final roleAsync = ref.watch(currentAccountingRoleProvider);
    final currentRole = roleAsync.valueOrNull;
    final canAccessReports =
        roleAsync.hasValue &&
        ref.watch(canAccessAccountingProvider(currentRole));
    final roleIsLoading = hasWorkspace && roleAsync.isLoading;
    final weeklyInsights = canAccessReports
        ? (workspaceId == null
              ? DashboardWeeklyInsights(
                  topEntity: 'Unassigned',
                  topCategory: 'Unassigned',
                  laborTotal: 0,
                  equipmentTotal: 0,
                  paymentSummary: {},
                  recentTransactions: [],
                )
              : ref
                    .watch(dashboardWeeklyInsightsProvider(workspaceId))
                    .valueOrNull)
        : null;

    final summaryAsync = canAccessReports
        ? ref.watch(reportSummaryProvider)
        : const AsyncData(<String, num>{});
    final metricsAsync = canAccessReports
        ? ref.watch(reportMetricsProvider)
        : const AsyncData<ReportMetrics?>(null);
    final categoryAsync = canAccessReports
        ? ref.watch(expensesByCategoryProvider)
        : const AsyncData(<String, double>{});
    final flowAsync = canAccessReports
        ? ref.watch(monthlyFlowProvider)
        : const AsyncData(<MonthlyFlowData>[]);
    final workersAsync = canAccessReports
        ? ref.watch(topWorkersProvider)
        : const AsyncData(<WorkerCostData>[]);
    final expensesAsync = canAccessReports
        ? ref.watch(reportExpensesProvider)
        : const AsyncData(<Expense>[]);
    final paymentsAsync = canAccessReports
        ? ref.watch(reportPaymentsProvider)
        : const AsyncData(<PaymentRecord>[]);
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final title = _ReportsHeaderTitle(
                        fallbackRoute: fallbackRoute,
                        title: l10n.t('reports'),
                      );
                      final actions = hasWorkspace && canAccessReports
                          ? _ReportsHeaderActions(
                              currentProjectId: currentProjectId,
                              weeklyInsights: weeklyInsights,
                              onExportProject: () async {
                                HapticFeedback.lightImpact();
                                final projects = ref
                                    .read(projectsProvider)
                                    .valueOrNull;
                                final metrics = ref
                                    .read(reportMetricsProvider)
                                    .valueOrNull;
                                final selectedProject = projects
                                    ?.where(
                                      (project) =>
                                          project.id == currentProjectId,
                                    )
                                    .firstOrNull;
                                if (selectedProject == null ||
                                    metrics == null) {
                                  return;
                                }
                                await _export(
                                  l10n: l10n,
                                  project: selectedProject,
                                  metrics: metrics,
                                  currency: currency,
                                );
                              },
                              onExportWeekly: () async {
                                HapticFeedback.lightImpact();
                                if (weeklyInsights == null) {
                                  return;
                                }
                                await _exportWeekly(
                                  l10n: l10n,
                                  insights: weeklyInsights,
                                  currency: currency,
                                );
                              },
                              onExportCombined: () async {
                                HapticFeedback.lightImpact();
                                final projects = ref
                                    .read(projectsProvider)
                                    .valueOrNull;
                                final metrics = ref
                                    .read(reportMetricsProvider)
                                    .valueOrNull;
                                final selectedProject = projects
                                    ?.where(
                                      (project) =>
                                          project.id == currentProjectId,
                                    )
                                    .firstOrNull;
                                if (selectedProject == null ||
                                    metrics == null ||
                                    weeklyInsights == null) {
                                  return;
                                }
                                await _exportCombined(
                                  l10n: l10n,
                                  project: selectedProject,
                                  metrics: metrics,
                                  insights: weeklyInsights,
                                  currency: currency,
                                );
                              },
                              onOpenEntitySummary: () {
                                HapticFeedback.lightImpact();
                                context.push(AppRoutes.entitySummaryPath());
                              },
                              onBuildCustomReport: () async {
                                HapticFeedback.lightImpact();
                                final projects = ref
                                    .read(projectsProvider)
                                    .valueOrNull;
                                final selectedProject = projects
                                    ?.where(
                                      (project) =>
                                          project.id == currentProjectId,
                                    )
                                    .firstOrNull;
                                if (selectedProject == null ||
                                    weeklyInsights == null) {
                                  return;
                                }
                                await _openCustomReportBuilder(
                                  l10n: l10n,
                                  project: selectedProject,
                                  insights: weeklyInsights,
                                  currency: currency,
                                );
                              },
                            )
                          : null;

                      if (actions == null) {
                        return title;
                      }

                      if (constraints.maxWidth < 560) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 12),
                            actions,
                          ],
                        );
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 16),
                          Flexible(child: actions),
                        ],
                      );
                    },
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

                        return BelowDropdownField<String>(
                          label: l10n.t('selectProject'),
                          value: projects.any((p) => p.id == currentProjectId)
                              ? currentProjectId
                              : null,
                          entries: projects
                              .map(
                                (project) => DropdownMenuEntry(
                                  value: project.id,
                                  label: project.name,
                                ),
                              )
                              .toList(),
                          onSelected: (value) {
                            ref.read(reportProjectIdProvider.notifier).state =
                                value;
                          },
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (error, _) => Text(error.toString()),
                    ),
                  ),
                ),
              if (roleIsLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LoadingWidget(),
                )
              else if (hasWorkspace && !canAccessReports)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _ErrorCard(message: l10n.t('reportAccessDenied')),
                    ),
                  ),
                )
              else if (currentProjectId == null)
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
                                      summary['net'] ?? 0,
                                      currencyCode: currency,
                                      locale: locale,
                                    ),
                                    color: (summary['net'] ?? 0) >= 0
                                        ? AppColors.success
                                        : AppColors.danger,
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                ],
                              ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 24),
                      categoryAsync.when(
                        data: (data) => CategoryPieChart(
                          data: data,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      flowAsync.when(
                        data: (data) => MonthlyFlowChart(
                          data: data,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      flowAsync.when(
                        data: (data) => CashflowLineChart(
                          data: data,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 24),
                      expensesAsync.when(
                        data: (expenses) => RecentExpensesTable(
                          expenses: expenses,
                          locale: locale,
                        ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      paymentsAsync.when(
                        data: (payments) => RecentPaymentsTable(
                          payments: payments,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
                        loading: () => const _LoadingWidget(),
                      ),
                      const SizedBox(height: 16),
                      workersAsync.when(
                        data: (workers) => WorkerCostTable(
                          workers: workers,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
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
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: AppColors.textBody),
                                ),
                              ),
                        error: (error, _) =>
                            _ErrorCard(message: error.toString()),
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
                                  style: Theme.of(context).textTheme.bodySmall
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

class _ReportsHeaderTitle extends StatelessWidget {
  const _ReportsHeaderTitle({required this.fallbackRoute, required this.title});

  final String fallbackRoute;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppBackButton(fallbackRoute: fallbackRoute),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportsHeaderActions extends StatelessWidget {
  const _ReportsHeaderActions({
    required this.currentProjectId,
    required this.weeklyInsights,
    required this.onExportProject,
    required this.onExportWeekly,
    required this.onExportCombined,
    required this.onOpenEntitySummary,
    required this.onBuildCustomReport,
  });

  final String? currentProjectId;
  final DashboardWeeklyInsights? weeklyInsights;
  final VoidCallback onExportProject;
  final VoidCallback onExportWeekly;
  final VoidCallback onExportCombined;
  final VoidCallback onOpenEntitySummary;
  final VoidCallback onBuildCustomReport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (currentProjectId != null)
            _ExportButton(label: l10n.t('exportPdf'), onTap: onExportProject),
          if (currentProjectId != null) const SizedBox(width: 8),
          if (weeklyInsights != null)
            _ExportButton(
              label: l10n.t('exportWeeklyReport'),
              onTap: onExportWeekly,
            ),
          if (weeklyInsights != null && currentProjectId != null)
            const SizedBox(width: 8),
          if (weeklyInsights != null && currentProjectId != null)
            _ExportButton(
              label: l10n.t('exportCombinedReport'),
              onTap: onExportCombined,
            ),
          const SizedBox(width: 8),
          _ExportButton(
            label: l10n.t('entitySummary'),
            onTap: onOpenEntitySummary,
          ),
          if (currentProjectId != null && weeklyInsights != null)
            const SizedBox(width: 8),
          if (currentProjectId != null && weeklyInsights != null)
            _ExportButton(
              label: l10n.t('buildCustomReport'),
              onTap: onBuildCustomReport,
            ),
        ],
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textBody),
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
