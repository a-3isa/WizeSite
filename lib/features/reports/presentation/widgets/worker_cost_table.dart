import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:flutter/material.dart';

class WorkerCostTable extends StatelessWidget {
  const WorkerCostTable({
    required this.workers,
    required this.currency,
    required this.locale,
    super.key,
  });

  final List<WorkerCostData> workers;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              l10n.t('topWorkers'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.tokens.text,
              ),
            ),
          ),
          if (workers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  l10n.t('noDataYet'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.tokens.textMuted,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  context.tokens.surface2,
                ),
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                columnSpacing: 24,
                headingTextStyle: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.tokens.textMuted,
                    ),
                dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.tokens.text,
                  fontWeight: FontWeight.w500,
                ),
                columns: [
                  DataColumn(label: Text(l10n.t('workerName'))),
                  DataColumn(label: Text(l10n.t('daysWorked')), numeric: true),
                  DataColumn(
                    label: Text(l10n.t('totalLaborCost')),
                    numeric: true,
                  ),
                ],
                rows: workers.map((w) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: context.tokens.accent.withValues(
                                  alpha: 0.12,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.engineering,
                                size: 14,
                                color: context.tokens.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(w.name),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          w.totalDays.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.money(
                            w.totalCost,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.tokens.accent,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
