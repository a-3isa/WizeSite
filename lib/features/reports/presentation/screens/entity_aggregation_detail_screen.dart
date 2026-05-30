import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/features/reports/data/entity_aggregation_providers.dart';
import 'package:flutter/material.dart';

class EntityAggregationDetailScreen extends StatelessWidget {
  const EntityAggregationDetailScreen({required this.summary, super.key});

  final EntitySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(summary.entityName)),
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
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium,
      ),
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
