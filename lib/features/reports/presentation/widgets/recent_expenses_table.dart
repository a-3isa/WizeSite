import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RecentExpensesTable extends StatelessWidget {
  const RecentExpensesTable({
    required this.expenses,
    required this.locale,
    super.key,
  });

  final List<Expense> expenses;
  final String locale;

  Color _colorFor(BuildContext context, String category) {
    final t = context.tokens;
    return switch (category) {
      'labor' => t.accent,
      'materials' => const Color(0xFF3B82F6),
      'equipment' => t.warning,
      'transport' => const Color(0xFF14B8A6),
      _ => t.textFaint,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = expenses.take(5).toList();

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
              l10n.t('recentExpenses'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.tokens.text,
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
                columnSpacing: 20,
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
                  DataColumn(label: Text(l10n.t('date'))),
                  DataColumn(label: Text(l10n.t('category'))),
                  DataColumn(label: Text(l10n.t('project'))),
                  DataColumn(label: Text(l10n.t('amount')), numeric: true),
                ],
                rows: items.map((e) {
                  final color = _colorFor(context, e.category);
                  return DataRow(
                    cells: [
                      DataCell(Text(DateFormat('dd/MM').format(e.date))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
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
                          Formatters.money(
                            e.amount,
                            currencyCode: e.currency,
                            locale: locale,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.tokens.expense,
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
