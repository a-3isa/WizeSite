import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class MonthlyFlowChart extends StatelessWidget {
  const MonthlyFlowChart({
    required this.data,
    required this.currency,
    required this.locale,
    this.showIncome = true,
    super.key,
  });

  final List<MonthlyFlowData> data;
  final String currency;
  final String locale;
  final bool showIncome;

  static const _monthAbbr = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasData = data.any(
      (d) => d.expenses > 0 || (showIncome && d.income > 0),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('monthlyCashFlow'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.tokens.text,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (showIncome)
                _DotLabel(
                  color: context.tokens.income,
                  label: l10n.t('totalIncome'),
                ),
              _DotLabel(
                color: context.tokens.expense,
                label: l10n.t('totalExpenses'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
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
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _maxY(),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) =>
                          context.tokens.text.withValues(alpha: 0.9),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final isIncome = showIncome && rodIndex == 0;
                        return BarTooltipItem(
                          Formatters.money(
                            rod.toY,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          TextStyle(
                            color: isIncome
                                ? context.tokens.income
                                : context.tokens.expense,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= data.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _monthAbbr[data[idx].month.month - 1],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.tokens.textMuted,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(
                            _formatCompact(value),
                            style: TextStyle(
                              fontSize: 10,
                              color: context.tokens.textMuted,
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _maxY() / 4,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: context.tokens.border, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(data.length, (i) {
                    final d = data[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        if (showIncome)
                          BarChartRodData(
                            toY: d.income,
                            color: context.tokens.income,
                            width: 14,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            gradient: LinearGradient(
                              colors: [
                                context.tokens.income,
                                context.tokens.income.withValues(alpha: 0.7),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        BarChartRodData(
                          toY: d.expenses,
                          color: context.tokens.expense,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          gradient: LinearGradient(
                            colors: [
                              context.tokens.expense,
                              context.tokens.expense.withValues(alpha: 0.7),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 400),
              ),
            ),
        ],
      ),
    );
  }

  double _maxY() {
    double max = 0;
    for (final d in data) {
      if (showIncome && d.income > max) max = d.income;
      if (d.expenses > max) max = d.expenses;
    }
    return max == 0 ? 100 : max * 1.15;
  }

  String _formatCompact(double value) {
    return Formatters.compactNumber(value, locale: locale);
  }
}

class _DotLabel extends StatelessWidget {
  const _DotLabel({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.tokens.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
