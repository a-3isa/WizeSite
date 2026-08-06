import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/features/expenses/domain/expense.dart';
import 'package:buildtrack_app/features/expenses/presentation/models/expense_group.dart';
import 'package:flutter/material.dart';

typedef ExpenseGroupItemBuilder =
    Widget Function(BuildContext context, Expense expense);

class ExpenseGroupSection extends StatelessWidget {
  const ExpenseGroupSection({
    required this.group,
    required this.itemBuilder,
    this.initiallyExpanded = true,
    super.key,
  });

  final ExpenseGroup group;
  final ExpenseGroupItemBuilder itemBuilder;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final countLabel = group.transactionCount == 1
        ? l10n.t('transactionSingular')
        : l10n.t('transactionPlural');
    return ExpansionTile(
      key: PageStorageKey<String>('expense_group_${group.id}'),
      initiallyExpanded: initiallyExpanded,
      title: Text(group.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${group.transactionCount} $countLabel'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            group.totalAmount.toStringAsFixed(2),
            style: theme.textTheme.titleSmall,
          ),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        for (final expense in group.items) itemBuilder(context, expense),
      ],
    );
  }
}
