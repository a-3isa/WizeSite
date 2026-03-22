import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
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
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  void didUpdateWidget(ReportsScreen oldWidget) {
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
    required Map<String, num> summary,
  }) async {
    final brandColor = PdfColor.fromHex('#F59E0B'); // constructionOrange
    final textDark = PdfColor.fromHex('#0F172A');
    final textBody = PdfColor.fromHex('#64748B');
    final surfaceGrey = PdfColor.fromHex('#F8FAFC');

    // Load Unicode fonts (Cairo supports both English and Arabic)
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final document = pw.Document();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ─── Header ──────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        l10n.t('buildozerFinancialReport').toUpperCase(),
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 24,
                          color: brandColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'WizeSite Analytics',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: textBody,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: surfaceGrey,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          '${l10n.t('generated')}:',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: textBody,
                          ),
                        ),
                        pw.Text(
                          DateTime.now().toString().split('.')[0], // simpler date format
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 10,
                            color: textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 32),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 32),

              // ─── Document Title ──────────────────────────────
              pw.Text(
                'Project Report', // standard string, hardcoded for simplicity right now
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 18,
                  color: textDark,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Project: ${project.name}',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 14,
                  color: textDark,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Status: ${project.isArchived ? 'Archived' : (project.status == 'active' ? 'Active' : project.status.toUpperCase())}',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 12,
                  color: textBody,
                ),
              ),
              pw.SizedBox(height: 24),

              // ─── Financial Table ─────────────────────────────
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Table(
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    _buildPdfTableRow(
                      label: l10n.t('totalIncomeLabel', params: {'value': ''}).replaceAll(':', '').trim(),
                      value: (summary['totalIncome'] ?? 0).toStringAsFixed(0),
                      isHeader: true,
                      font: font,
                      fontBold: fontBold,
                      textColor: textDark,
                      backgroundColor: surfaceGrey,
                    ),
                    _buildPdfTableRow(
                      label: l10n.t('totalExpensesLabel', params: {'value': ''}).replaceAll(':', '').trim(),
                      value: (summary['totalExpenses'] ?? 0).toStringAsFixed(0),
                      font: font,
                      fontBold: fontBold,
                      textColor: textDark,
                    ),
                    _buildPdfTableRow(
                      label: l10n.t('netProfitLoss', params: {'value': ''}).replaceAll(':', '').trim(),
                      value: (summary['net'] ?? 0).toStringAsFixed(0),
                      isFooter: true,
                      font: font,
                      fontBold: fontBold,
                      textColor: (summary['net'] ?? 0) >= 0 ? PdfColor.fromHex('#10B981') : PdfColor.fromHex('#EF4444'),
                      backgroundColor: surfaceGrey,
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // ─── Footer ──────────────────────────────────────
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Generated securely by WizeSite App',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 10,
                    color: textBody,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => document.save());
  }
  pw.TableRow _buildPdfTableRow({
    required String label,
    required String value,
    required pw.Font font,
    required pw.Font fontBold,
    required PdfColor textColor,
    PdfColor? backgroundColor,
    bool isHeader = false,
    bool isFooter = false,
  }) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        border: isFooter ? pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 2)) : null,
      ),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: isHeader || isFooter ? fontBold : font,
              fontSize: isHeader || isFooter ? 14 : 12,
              color: isHeader || isFooter ? PdfColor.fromHex('#0F172A') : PdfColor.fromHex('#64748B'),
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: isHeader || isFooter ? 14 : 12,
              color: textColor,
            ),
          ),
        ),
      ],
    );

  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final currentProjectId = ref.watch(reportProjectIdProvider);
    final projectsAsync = ref.watch(allProjectsProvider);
    final summaryAsync = ref.watch(reportSummaryProvider);
    final hasWorkspace = workspaceId != null;

    // Chart data
    final categoryAsync = ref.watch(expensesByCategoryProvider);
    final flowAsync = ref.watch(monthlyFlowProvider);
    final workersAsync = ref.watch(topWorkersProvider);
    final expensesAsync = ref.watch(reportExpensesProvider);
    final paymentsAsync = ref.watch(reportPaymentsProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ─── Header ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.t('reports'),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: AppColors.textDark,
                              ),
                    ),
                    if (hasWorkspace && currentProjectId != null)
                      _ExportButton(
                        label: l10n.t('exportPdf'),
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final summaryResult = ref.read(reportSummaryProvider);
                          final summaryValue = summaryResult.valueOrNull;
                          final allProjs = ref.read(allProjectsProvider).valueOrNull ?? [];
                          final selectedProject = allProjs.where((p) => p.id == currentProjectId).firstOrNull;
                          if (summaryValue != null && selectedProject != null && context.mounted) {
                            await _export(
                              l10n: l10n,
                              project: selectedProject,
                              summary: summaryValue,
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
            // ─── Project Dropdown ────────────────────────────
            if (hasWorkspace)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: projectsAsync.when(
                    data: (projects) {
                      if (projects.isEmpty) {
                        return Text(
                          l10n.t('noProjectsYet'),
                          style: TextStyle(color: AppColors.textBody),
                        );
                      }
                      
                      return DropdownButtonFormField<String>(
                        initialValue: projects.any((p) => p.id == currentProjectId)
                            ? currentProjectId
                            : null,
                        hint: Text(
                          'Select a Project', // Consider moving to localizations later
                          style: TextStyle(color: AppColors.textBody),
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.borderGrey),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.borderGrey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppColors.constructionOrange),
                          ),
                        ),
                        items: projects.map((p) {
                          final isArchived = p.isArchived;
                          final isActive = p.status == 'active' && !isArchived;
                          final statusLabel = isArchived ? 'Archived' : (isActive ? 'Active' : p.status.toUpperCase());
                          final statusColor = isActive ? AppColors.success : AppColors.danger;

                          return DropdownMenuItem(
                            value: p.id,
                            child: Row(
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            ref.read(reportProjectIdProvider.notifier).state = val;
                          }
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text(err.toString()),
                  ),
                ),
              ),

            // ─── If No Project Selected ──────────────────────
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
                        'Please select a project to view its report.', // Add to l10n later if needed
                        style: TextStyle(color: AppColors.textBody, fontSize: 16),
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
                  // ─── Financial Summary ─────────────────────
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
                                    (summary['net'] ?? 0).toStringAsFixed(0),
                                color: (summary['net'] ?? 0) >= 0
                                    ? AppColors.success
                                    : AppColors.danger,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            ],
                          ),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Expense Breakdown ─────────────────────
                  const SizedBox(height: 24),
                  categoryAsync.when(
                    data: (data) => CategoryPieChart(data: data),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Monthly Cash Flow ─────────────────────
                  const SizedBox(height: 16),
                  flowAsync.when(
                    data: (data) => MonthlyFlowChart(data: data),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Net Cash Flow Trend ───────────────────
                  const SizedBox(height: 16),
                  flowAsync.when(
                    data: (data) => CashflowLineChart(data: data),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Recent Expenses ───────────────────────
                  const SizedBox(height: 24),
                  expensesAsync.when(
                    data: (expenses) =>
                        RecentExpensesTable(expenses: expenses),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Recent Payments ───────────────────────
                  const SizedBox(height: 16),
                  paymentsAsync.when(
                    data: (payments) =>
                        RecentPaymentsTable(payments: payments),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Worker Cost Summary ───────────────────
                  const SizedBox(height: 16),
                  workersAsync.when(
                    data: (workers) => WorkerCostTable(workers: workers),
                    error: (e, _) => _ErrorCard(message: e.toString()),
                    loading: () => const _LoadingWidget(),
                  ),

                  // ─── Usage footer ──────────────────────────
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
                                  'limit':
                                      '${usage.limits.expensesPerMonth}',
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
                    error: (error, stackTrace) => const SizedBox.shrink(),
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

// ─── Helper widgets ──────────────────────────────────────────────────

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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textBody,
              ),
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
    final isIndexError = message.contains('requires an index');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: AppColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isIndexError 
                      ? 'Service initialization required. Please check console logs for the index creation link.' 
                      : message,
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (isIndexError) ...[
            const SizedBox(height: 12),
            const Text(
              'Firestore requires a composite index for this report. If you haven\'t already, please click the link in the terminal/console to create it.',
              style: TextStyle(fontSize: 12, color: AppColors.textBody),
            ),
          ],
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
