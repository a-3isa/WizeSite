import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/features/subscription/domain/usage_models.dart';
import 'package:flutter/material.dart';

class UsageCard extends StatelessWidget {
  const UsageCard({required this.usage, super.key});

  final UsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('monthlyUsage'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _UsageRow(
              label: l10n.t('activeProjects'),
              current: usage.activeProjects,
              limit: usage.limits.activeProjects,
            ),
            _UsageRow(
              label: l10n.t('expenses'),
              current: usage.expensesCount,
              limit: usage.limits.expensesPerMonth,
            ),
            _UsageRow(
              label: l10n.t('payments'),
              current: usage.paymentsCount,
              limit: usage.limits.paymentsPerMonth,
            ),
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
    final isNearLimit = ratio >= 0.8;
    final color = isNearLimit ? AppColors.warning : AppColors.success;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text('$current / $limit')],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: ratio,
            backgroundColor: AppColors.lightGray,
            color: color,
          ),
        ],
      ),
    );
  }
}
