import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/accounting_access_provider.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/below_dropdown_field.dart';
import 'package:buildtrack_app/core/widgets/metric_card.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/dashboard/data/dashboard_providers.dart';
import 'package:buildtrack_app/features/expenses/data/expense_repository.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/payments/data/payment_repository.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:buildtrack_app/features/reports/data/report_project_selector_provider.dart';
import 'package:buildtrack_app/features/reports/domain/report_scope.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/cashflow_line_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/category_pie_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/monthly_flow_chart.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/recent_expenses_table.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/recent_payments_table.dart';
import 'package:buildtrack_app/features/reports/presentation/widgets/worker_cost_table.dart';
import 'package:buildtrack_app/features/reports/services/report_export_data_builder.dart';
import 'package:buildtrack_app/features/reports/services/report_chart_exporter.dart';
import 'package:buildtrack_app/features/reports/services/report_document_actions.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    this.projectId,
    this.exportDataBuilder,
    this.documentActions,
    this.chartExporter,
    super.key,
  });

  final String? projectId;
  final ReportExportDataBuilder? exportDataBuilder;
  final ReportDocumentActions? documentActions;
  final ReportChartExporter? chartExporter;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportExportProgress? _exportProgress;
  bool _isExporting = false;
  bool _cancelExport = false;

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
        final scope = ref.read(reportScopeProvider);
        ref.read(reportScopeProvider.notifier).state = scope.copyWith(
          projectId: widget.projectId,
        );
      }
    });
  }

  Future<void> _pickScopeDate({required bool start}) async {
    final scope = ref.read(effectiveReportScopeProvider);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: start ? scope.startDate : scope.endDate,
    );
    if (picked == null || !mounted) return;
    final next = start
        ? scope.copyWith(
            startDate: DateTime(picked.year, picked.month, picked.day),
          )
        : scope.copyWith(
            endDate: DateTime(
              picked.year,
              picked.month,
              picked.day,
              23,
              59,
              59,
              999,
            ),
          );
    if (next.startDate.isAfter(next.endDate)) return;
    ref.read(reportScopeProvider.notifier).state = next;
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
    final scope = ref.read(effectiveReportScopeProvider);
    DateTime? startDate = scope.startDate;
    DateTime? endDate = scope.endDate;

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
    setState(() {
      _isExporting = true;
      _cancelExport = false;
      _exportProgress = const ReportExportProgress(
        stage: ReportExportStage.expenses,
        loadedRecords: 0,
      );
    });
    try {
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      if (workspaceId == null || workspaceId.isEmpty) {
        _showExportError(l10n, StateError('missing workspace'));
        return;
      }

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
      final reportData =
          await (widget.exportDataBuilder ??
                  ReportExportDataBuilder(
                    expenseRepository: ref.read(expenseRepositoryProvider),
                    paymentRepository: ref.read(paymentRepositoryProvider),
                  ))
              .build(
                workspaceId: workspaceId,
                projectId: project.id,
                startDate: effectiveStartDate,
                endDate: inclusiveEndDate,
                includeExpenses: includeExpenses,
                includePayments: includePayments,
                includeEntities: includeEntities,
                includeDaily: includeDaily,
                includeWeekly: includeWeekly,
                isCancelled: () => _cancelExport,
                onProgress: (progress) {
                  if (mounted) {
                    setState(() => _exportProgress = progress);
                  }
                },
              );

      final exporter = const ReportPdfExporter();
      final documentBytes = await exporter.buildCustomReportPdf(
        l10n: l10n,
        project: project,
        expenses: reportData.expenses,
        payments: reportData.payments,
        insights: includeWeekly ? reportData.insights : insights,
        entitySummaries: reportData.entitySummaries,
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
    } on ReportExportCancelled {
      // Cancellation is user initiated and does not surface as an error.
    } catch (error) {
      _showExportError(l10n, error);
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = null;
        });
      }
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

  Future<void> _shareChart({
    required AppLocalizations l10n,
    required String filename,
    required Future<Uint8List> Function(ReportChartExporter exporter) build,
  }) async {
    final bytes = await build(
      widget.chartExporter ?? const ReportChartExporter(),
    );
    final result = await (widget.documentActions ?? ReportDocumentActions())
        .shareDocument(bytes: bytes, filename: filename);
    if (result.isFailed) {
      _showExportError(l10n, result.error ?? StateError('chart share failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final reportScope = ref.watch(effectiveReportScopeProvider);
    final currentProjectId = reportScope.projectId;
    final projectsAsync = ref.watch(projectsProvider);
    final selectorState = ref.watch(reportProjectSelectorProvider);
    final selectorProjects = selectorState.projects;
    final availableProjects = selectorProjects.isNotEmpty
        ? selectorProjects
        : projectsAsync.value ?? const <Project>[];
    final currency =
        ref.watch(currentUserSettingsProvider).value?.defaultCurrency ?? 'EGP';
    final hasWorkspace = workspaceId != null;
    final roleAsync = ref.watch(currentAccountingRoleProvider);
    final currentRole = roleAsync.value;
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
              : ref.watch(dashboardWeeklyInsightsProvider(workspaceId)).value)
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
                                final metrics = ref
                                    .read(reportMetricsProvider)
                                    .value;
                                final selectedProject = availableProjects
                                    .where(
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
                                final metrics = ref
                                    .read(reportMetricsProvider)
                                    .value;
                                final selectedProject = availableProjects
                                    .where(
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
                                final selectedProject = availableProjects
                                    .where(
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
                    child: _ReportScopeControls(
                      scope: reportScope,
                      projects: availableProjects,
                      selectorState: selectorState,
                      onProjectSelected: (value) {
                        ref.read(reportProjectIdProvider.notifier).state =
                            value;
                        ref.read(reportScopeProvider.notifier).state =
                            reportScope.copyWith(projectId: value);
                      },
                      onToggleArchived: (value) => ref
                          .read(reportProjectSelectorProvider.notifier)
                          .showArchived(value),
                      onLoadMore: () => ref
                          .read(reportProjectSelectorProvider.notifier)
                          .loadMore(),
                      onPickStart: () => _pickScopeDate(start: true),
                      onPickEnd: () => _pickScopeDate(start: false),
                    ),
                  ),
                ),
              if (_isExporting)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LinearProgressIndicator(),
                            const SizedBox(height: 10),
                            Text(
                              l10n.t(
                                'reportExportProgress',
                                params: {
                                  'count':
                                      '${_exportProgress?.loadedRecords ?? 0}',
                                },
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () =>
                                    setState(() => _cancelExport = true),
                                child: Text(l10n.t('cancelExport')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (roleIsLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppLoadingSkeleton(),
                )
              else if (hasWorkspace && !canAccessReports)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: AppRecoverableError(
                        message: l10n.t('reportAccessDenied'),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      SectionHeader(title: l10n.t('currentSnapshot')),
                      const SizedBox(height: 12),
                      summaryAsync.whenStale(
                        data: (summary) => summary.isEmpty
                            ? AppEmptyState(
                                message: l10n.t('noWorkspaceSelected'),
                              )
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
                                    color: context.tokens.expense,
                                    icon: Icons.trending_down,
                                  ),
                                  MetricCard(
                                    label: l10n.t('totalIncome'),
                                    value: Formatters.money(
                                      summary['totalIncome'] ?? 0,
                                      currencyCode: currency,
                                      locale: locale,
                                    ),
                                    color: context.tokens.income,
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
                                        ? context.tokens.income
                                        : context.tokens.expense,
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                ],
                              ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 24),
                      categoryAsync.whenStale(
                        data: (data) => _ShareableChart(
                          onShare: data.values.any((value) => value != 0)
                              ? () => _shareChart(
                                  l10n: l10n,
                                  filename: 'expense-breakdown.pdf',
                                  build: (exporter) =>
                                      exporter.buildCategoryChartPdf(
                                        title: l10n.t('expenseBreakdown'),
                                        categoryTotals: data,
                                        currency: currency,
                                        emptyLabel: l10n.t('noData'),
                                      ),
                                )
                              : null,
                          child: CategoryPieChart(
                            data: data,
                            currency: currency,
                            locale: locale,
                          ),
                        ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 16),
                      flowAsync.whenStale(
                        data: (data) => _ShareableChart(
                          onShare:
                              data.any(
                                (item) =>
                                    item.expenses != 0 || item.income != 0,
                              )
                              ? () => _shareChart(
                                  l10n: l10n,
                                  filename: 'monthly-flow.pdf',
                                  build: (exporter) =>
                                      exporter.buildMonthlyFlowChartPdf(
                                        title: l10n.t('monthlyCashFlow'),
                                        points: data,
                                        currency: currency,
                                        emptyLabel: l10n.t('noData'),
                                        expensesLabel: l10n.t('expenses'),
                                        incomeLabel: l10n.t('income'),
                                      ),
                                )
                              : null,
                          child: MonthlyFlowChart(
                            data: data,
                            currency: currency,
                            locale: locale,
                          ),
                        ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 16),
                      flowAsync.whenStale(
                        data: (data) => _ShareableChart(
                          onShare:
                              data.any(
                                (item) =>
                                    item.expenses != 0 || item.income != 0,
                              )
                              ? () => _shareChart(
                                  l10n: l10n,
                                  filename: 'cashflow-trend.pdf',
                                  build: (exporter) =>
                                      exporter.buildCashflowChartPdf(
                                        title: l10n.t('cashFlowTrend'),
                                        expenses: data.fold(
                                          0,
                                          (sum, item) => sum + item.expenses,
                                        ),
                                        income: data.fold(
                                          0,
                                          (sum, item) => sum + item.income,
                                        ),
                                        currency: currency,
                                        emptyLabel: l10n.t('noData'),
                                        expensesLabel: l10n.t('expenses'),
                                        incomeLabel: l10n.t('income'),
                                      ),
                                )
                              : null,
                          child: CashflowLineChart(
                            data: data,
                            currency: currency,
                            locale: locale,
                          ),
                        ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 24),
                      expensesAsync.whenStale(
                        data: (expenses) => RecentExpensesTable(
                          expenses: expenses,
                          locale: locale,
                        ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 16),
                      paymentsAsync.whenStale(
                        data: (payments) => RecentPaymentsTable(
                          payments: payments,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 16),
                      workersAsync.whenStale(
                        data: (workers) => WorkerCostTable(
                          workers: workers,
                          currency: currency,
                          locale: locale,
                        ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(),
                      ),
                      const SizedBox(height: 16),
                      metricsAsync.whenStale(
                        data: (metrics) => metrics == null
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.tokens.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: context.tokens.border,
                                  ),
                                ),
                                child: Text(
                                  '${metrics.projectName} • ${l10n.projectStatusLabel(metrics.status)}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: context.tokens.textMuted),
                                ),
                              ),
                        error: (error, _) => AppRecoverableError(
                          message: appErrorMessage(l10n, error),
                        ),
                        loading: () => const AppLoadingSkeleton(
                          lineCount: 2,
                          padding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 24),
                      usageAsync.whenStale(
                        data: (usage) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: context.tokens.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.tokens.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pie_chart_outline,
                                size: 20,
                                color: context.tokens.textMuted,
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
                                      ?.copyWith(color: context.tokens.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                        loading: () => const AppLoadingSkeleton(
                          lineCount: 3,
                          padding: EdgeInsets.symmetric(vertical: 8),
                        ),
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

class _ReportScopeControls extends StatelessWidget {
  const _ReportScopeControls({
    required this.scope,
    required this.projects,
    required this.selectorState,
    required this.onProjectSelected,
    required this.onToggleArchived,
    required this.onLoadMore,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final ReportScope scope;
  final List<Project> projects;
  final ReportProjectSelectorState selectorState;
  final ValueChanged<String?> onProjectSelected;
  final ValueChanged<bool> onToggleArchived;
  final VoidCallback onLoadMore;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  String _date(DateTime value) => value.toIso8601String().split('T').first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (selectorState.isLoading && projects.isEmpty) {
      return const AppLoadingSkeleton(lineCount: 2);
    }
    if (selectorState.error != null && projects.isEmpty) {
      return AppRecoverableError(
        message: appErrorMessage(l10n, selectorState.error!),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('reportScope'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.tokens.text,
          ),
        ),
        const SizedBox(height: 10),
        if (projects.isEmpty)
          AppEmptyState(message: l10n.t('noProjectsYet'))
        else
          BelowDropdownField<String>(
            label: l10n.t('selectProject'),
            value: projects.any((item) => item.id == scope.projectId)
                ? scope.projectId
                : '',
            entries: [
              DropdownMenuEntry(value: '', label: l10n.t('allProjectsOption')),
              for (final project in projects)
                DropdownMenuEntry(value: project.id, label: project.name),
            ],
            onSelected: onProjectSelected,
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: selectorState.showingArchived,
              label: Text(l10n.t('showArchivedProjects')),
              onSelected: onToggleArchived,
            ),
            OutlinedButton.icon(
              onPressed: onPickStart,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                l10n.t(
                  'reportStartDate',
                  params: {'value': _date(scope.startDate)},
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onPickEnd,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(
                l10n.t(
                  'reportEndDate',
                  params: {'value': _date(scope.endDate)},
                ),
              ),
            ),
            if (selectorState.hasMore)
              TextButton.icon(
                onPressed: selectorState.isLoadingMore ? null : onLoadMore,
                icon: selectorState.isLoadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(l10n.t('loadMore')),
              ),
          ],
        ),
      ],
    );
  }
}

class _ShareableChart extends StatelessWidget {
  const _ShareableChart({required this.child, required this.onShare});

  final Widget child;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    if (onShare == null) return child;
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        child,
        PositionedDirectional(
          top: 8,
          end: 8,
          child: IconButton.filledTonal(
            tooltip: l10n.t('shareChart'),
            onPressed: onShare,
            icon: const Icon(Icons.share_outlined),
          ),
        ),
      ],
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
              color: context.tokens.text,
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
    return PopupMenuButton<_ReportAction>(
      tooltip: l10n.t('reportExports'),
      onSelected: (action) {
        switch (action) {
          case _ReportAction.project:
            onExportProject();
          case _ReportAction.weekly:
            onExportWeekly();
          case _ReportAction.combined:
            onExportCombined();
          case _ReportAction.entities:
            onOpenEntitySummary();
          case _ReportAction.custom:
            onBuildCustomReport();
        }
      },
      itemBuilder: (context) => [
        if (currentProjectId != null)
          PopupMenuItem(
            value: _ReportAction.project,
            child: Text(l10n.t('exportPdf')),
          ),
        if (weeklyInsights != null)
          PopupMenuItem(
            value: _ReportAction.weekly,
            child: Text(l10n.t('exportWeeklyReport')),
          ),
        if (weeklyInsights != null && currentProjectId != null)
          PopupMenuItem(
            value: _ReportAction.combined,
            child: Text(l10n.t('exportCombinedReport')),
          ),
        PopupMenuItem(
          value: _ReportAction.entities,
          child: Text(l10n.t('entitySummary')),
        ),
        if (currentProjectId != null && weeklyInsights != null)
          PopupMenuItem(
            value: _ReportAction.custom,
            child: Text(l10n.t('buildCustomReport')),
          ),
      ],
      child: _ExportButton(label: l10n.t('reportExports'), onTap: null),
    );
  }
}

enum _ReportAction { project, weekly, combined, entities, custom }

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.tokens.accent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 18,
                color: context.tokens.accent,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.tokens.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
