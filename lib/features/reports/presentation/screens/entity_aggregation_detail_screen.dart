import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:buildtrack_app/features/reports/services/report_pdf_exporter.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

typedef EntitySummaryPdfAction =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      EntitySummary summary,
    );

class EntityAggregationDetailScreen extends ConsumerWidget {
  const EntityAggregationDetailScreen({
    required this.summary,
    this.onExportPdf,
    super.key,
  });

  final EntitySummary summary;
  final EntitySummaryPdfAction? onExportPdf;

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final injectedExport = onExportPdf;
      if (injectedExport != null) {
        await injectedExport(context, ref, summary);
      } else {
        await _buildAndPrintPdf(context, ref);
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(appErrorMessage(l10n, error))));
    }
  }

  Future<void> _buildAndPrintPdf(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final currency =
        ref.read(currentUserSettingsProvider).valueOrNull?.defaultCurrency ??
        'EGP';
    final bytes = await const ReportPdfExporter().buildEntitySummaryReportPdf(
      l10n: l10n,
      summaries: [summary],
      selectedType: 'all',
      currency: currency,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(summary.entityName),
        actions: [
          IconButton(
            tooltip: l10n.t('exportEntitySummary'),
            onPressed: () => _exportPdf(context, ref),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MetricRow(label: l10n.t('entityType'), value: summary.entityType),
          _MetricRow(
            label: l10n.t('totalExpenses'),
            value: summary.totalExpenses.toStringAsFixed(2),
          ),
          _MetricRow(
            label: l10n.t('totalPayments'),
            value: summary.totalPayments.toStringAsFixed(2),
          ),
          _MetricRow(
            label: l10n.t('netProfitLoss'),
            value: summary.net.toStringAsFixed(2),
          ),
          _MetricRow(
            label: l10n.t('transactions'),
            value: '${summary.transactionCount}',
          ),
          _MetricRow(
            label: l10n.t('attachments'),
            value: '${summary.attachmentCount}',
          ),
          const SizedBox(height: 16),
          _BreakdownSection(
            title: l10n.t('category'),
            values: summary.categoryBreakdown,
          ),
          const SizedBox(height: 16),
          _BreakdownSection(
            title: l10n.t('paymentBreakdown'),
            values: summary.paymentMethodBreakdown,
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({required this.title, required this.values});

  final String title;
  final Map<String, double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...values.entries.map(
          (entry) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.key),
            trailing: Text(entry.value.toStringAsFixed(2)),
          ),
        ),
      ],
    );
  }
}
