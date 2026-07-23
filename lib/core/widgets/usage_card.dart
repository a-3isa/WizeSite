import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:flutter/material.dart';

class UsageCard extends StatelessWidget {
  const UsageCard({required this.usage, super.key});

  final UsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: context.tokens.border,
        ), // Outline style card
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.data_usage,
                  color: context.tokens.accent,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.t('monthlyUsage'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _UsageRow(
              label: l10n.t('activeProjects'),
              current: usage.activeProjects,
              limit: usage.limits.activeProjects,
            ),
            const SizedBox(height: 16),
            _UsageRow(
              label: l10n.t('expenses'),
              current: usage.expensesCount,
              limit: usage.limits.expensesPerMonth,
            ),
            const SizedBox(height: 16),
            _UsageRow(
              label: l10n.t('payments'),
              current: usage.paymentsCount,
              limit: usage.limits.paymentsPerMonth,
            ),
            const SizedBox(height: 16),
            _UsageRow(
              label: l10n.t('workerEntries'),
              current: usage.workerEntriesCount,
              limit: usage.limits.workerEntriesPerMonth,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.label,
    required this.current,
    required this.limit,
  });

  final String label;
  final int current;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final ratio = limit == 0 ? 0.0 : (current / limit).clamp(0.0, 1.0);
    // Determine color based on threshold (e.g. 80% is warning, 100% is danger)
    final Color progressColor = ratio >= 1.0
        ? context.tokens.expense
        : (ratio >= 0.8 ? context.tokens.warning : context.tokens.income);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.tokens.text,
              ),
            ),
            Text(
              '$current / $limit',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: progressColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: progressColor.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
      ],
    );
  }
}
