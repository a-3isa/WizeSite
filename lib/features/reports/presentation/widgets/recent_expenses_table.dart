import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RecentExpensesTable extends StatelessWidget {
  const RecentExpensesTable({required this.expenses, super.key});

  final List<Expense> expenses;

  static const _categoryColors = <String, Color>{
    'labor': AppColors.constructionOrange,
    'materials': Color(0xFF3B82F6),
    'equipment': Color(0xFFF59E0B),
    'transport': Color(0xFF14B8A6),
    'other': Color(0xFF94A3B8),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = expenses.take(5).toList();

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
              l10n.t('recentExpenses'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
            ),
          ),
          if (items.isEmpty)
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
                columnSpacing: 20,
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
                  DataColumn(label: Text(l10n.t('date'))),
                  DataColumn(label: Text(l10n.t('category'))),
                  DataColumn(label: Text(l10n.t('project'))),
                  DataColumn(label: Text(l10n.t('amount')), numeric: true),
                ],
                rows: items.map((e) {
                  final color =
                      _categoryColors[e.category] ?? const Color(0xFF94A3B8);
                  return DataRow(cells: [
                    DataCell(Text(DateFormat('dd/MM').format(e.date))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n.expenseCategoryLabel(e.category),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          e.projectName.isEmpty ? '-' : e.projectName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        e.amount.toStringAsFixed(0),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
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
