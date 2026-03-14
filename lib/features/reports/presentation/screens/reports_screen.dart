import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:buildtrack_app/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:flutter/material.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('reports'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(l10n.t('projectFinancialReport')),
              subtitle: Text(l10n.t('projectFinancialReportSubtitle')),
              trailing: const Icon(Icons.picture_as_pdf),
              onTap: workspaceId == null
                  ? null
                  : () async {
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
                    },
            ),
          ),
          Card(
            child: ListTile(
              title: Text(l10n.t('expenseReport')),
              subtitle: Text(l10n.t('expenseReportSubtitle')),
              trailing: const Icon(Icons.table_chart),
            ),
          ),
          Card(
            child: ListTile(
              title: Text(l10n.t('workerCostReport')),
              subtitle: Text(l10n.t('workerCostReportSubtitle')),
              trailing: const Icon(Icons.groups),
            ),
          ),
          const SizedBox(height: 12),
          summaryAsync.when(
            data: (summary) => summary.isEmpty
                ? const SizedBox.shrink()
                : Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.t('currentSnapshot'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.t(
                              'totalProjects',
                              params: {
                                'value': '${summary['totalProjects']?.toInt() ?? 0}',
                              },
                            ),
                          ),
                          Text(
                            l10n.t(
                              'totalIncomeLabel',
                              params: {
                                'value':
                                    '${summary['totalIncome']?.toStringAsFixed(0) ?? 0}',
                              },
                            ),
                          ),
                          Text(
                            l10n.t(
                              'totalExpensesLabel',
                              params: {
                                'value':
                                    '${summary['totalExpenses']?.toStringAsFixed(0) ?? 0}',
                              },
                            ),
                          ),
                          Text(
                            l10n.t(
                              'netLabel',
                              params: {
                                'value': '${summary['net']?.toStringAsFixed(0) ?? 0}',
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            error: (e, _) => Text(e.toString()),
            loading: () => const CircularProgressIndicator(),
          ),
          const SizedBox(height: 12),
          usageAsync.when(
            data: (usage) => Text(
              l10n.t(
                'usagePeriod',
                params: {
                  'period': usage.periodKey,
                  'count': '${usage.expensesCount}',
                  'limit': '${usage.limits.expensesPerMonth}',
                },
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
