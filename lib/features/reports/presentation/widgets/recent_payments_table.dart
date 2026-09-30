import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/payments/domain/payment.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RecentPaymentsTable extends StatelessWidget {
  const RecentPaymentsTable({
    required this.payments,
    required this.currency,
    required this.locale,
    super.key,
  });

  final List<PaymentRecord> payments;
  final String currency;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = payments.take(5).toList();

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
              l10n.t('recentPayments'),
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
                  DataColumn(label: Text(l10n.t('date'))),
                  DataColumn(label: Text(l10n.t('paymentMethod'))),
                  DataColumn(label: Text(l10n.t('amount')), numeric: true),
                ],
                rows: items.map((p) {
                  return DataRow(
                    cells: [
                      DataCell(Text(DateFormat('dd/MM').format(p.date))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.tokens.income.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.paymentMethodLabel(p.paymentMethod),
                            style: TextStyle(
                              color: context.tokens.income,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          Formatters.money(
                            p.amount,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.tokens.income,
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
