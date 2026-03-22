import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:flutter/material.dart';

class WorkerCostTable extends StatelessWidget {
  const WorkerCostTable({required this.workers, super.key});

  final List<WorkerCostData> workers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderGrey),
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
                    color: AppColors.textDark,
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
                        color: AppColors.textBody,
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
                  AppColors.surfaceGrey,
                ),
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                columnSpacing: 24,
                headingTextStyle:
                    Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textBody,
                        ),
                dataTextStyle:
                    Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                columns: [
                  DataColumn(label: Text(l10n.t('workerName'))),
                  DataColumn(label: Text(l10n.t('daysWorked')), numeric: true),
                  DataColumn(
                      label: Text(l10n.t('totalLaborCost')), numeric: true),
                ],
                rows: workers.map((w) {
                  return DataRow(cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.constructionOrange
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.engineering,
                              size: 14,
                              color: AppColors.constructionOrange,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        w.totalCost.toStringAsFixed(0),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.constructionOrange,
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
