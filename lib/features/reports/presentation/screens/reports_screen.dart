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
    required BuildContext context,
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
              'BuildTrack Financial Report',
              style: pw.TextStyle(fontSize: 22),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Workspace: $workspaceId'),
            pw.Text('Generated: ${DateTime.now().toIso8601String()}'),
            pw.SizedBox(height: 20),
            pw.Text(
              'Total Projects: ${(summary['totalProjects'] ?? 0).toInt()}',
            ),
            pw.Text(
              'Active Projects: ${(summary['activeProjects'] ?? 0).toInt()}',
            ),
            pw.Text(
              'Total Expenses: ${(summary['totalExpenses'] ?? 0).toStringAsFixed(0)}',
            ),
            pw.Text(
              'Total Income: ${(summary['totalIncome'] ?? 0).toStringAsFixed(0)}',
            ),
            pw.Text(
              'Net Profit/Loss: ${(summary['net'] ?? 0).toStringAsFixed(0)}',
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => document.save());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    final usageAsync = ref.watch(currentUsageProvider);
    final summaryAsync = workspaceId == null
        ? const AsyncValue.data(<String, num>{})
        : ref.watch(dashboardSummaryProvider(workspaceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Project Financial Report'),
              subtitle: const Text(
                'Contract, expenses, payments, net profit/loss',
              ),
              trailing: const Icon(Icons.picture_as_pdf),
              onTap: workspaceId == null
                  ? null
                  : () async {
                      final summary = await ref.read(
                        dashboardSummaryProvider(workspaceId).future,
                      );
                      if (context.mounted) {
                        await _export(
                          context: context,
                          workspaceId: workspaceId,
                          summary: summary,
                        );
                      }
                    },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Expense Report'),
              subtitle: const Text('Breakdown by category and period'),
              trailing: const Icon(Icons.table_chart),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Worker Cost Report'),
              subtitle: const Text('Labor totals and worker entries'),
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
                          const Text(
                            'Current Snapshot',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Projects: ${summary['totalProjects']?.toInt() ?? 0}',
                          ),
                          Text(
                            'Income: ${summary['totalIncome']?.toStringAsFixed(0) ?? 0}',
                          ),
                          Text(
                            'Expenses: ${summary['totalExpenses']?.toStringAsFixed(0) ?? 0}',
                          ),
                          Text(
                            'Net: ${summary['net']?.toStringAsFixed(0) ?? 0}',
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
              'Usage period: ${usage.periodKey} | expenses ${usage.expensesCount}/${usage.limits.expensesPerMonth}',
            ),
            error: (_, _) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
