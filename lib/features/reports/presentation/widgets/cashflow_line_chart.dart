import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:buildtrack_app/features/reports/data/reports_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class CashflowLineChart extends StatelessWidget {
  const CashflowLineChart({
    required this.data,
    required this.currency,
    required this.locale,
    super.key,
  });

  final List<MonthlyFlowData> data;
  final String currency;
  final String locale;

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
    final hasData = data.any((d) => d.expenses > 0 || d.income > 0);

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
            l10n.t('cashFlowTrend'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.tokens.text,
            ),
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  l10n.t('noDataYet'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: context.tokens.textMuted),
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _interval(),
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: context.tokens.border, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
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
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
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
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) =>
                          context.tokens.text.withValues(alpha: 0.9),
                      getTooltipItems: (spots) => spots.map((spot) {
                        final net = spot.y;
                        return LineTooltipItem(
                          Formatters.money(
                            net,
                            currencyCode: currency,
                            locale: locale,
                          ),
                          TextStyle(
                            color: net >= 0
                                ? AppColors.success
                                : AppColors.danger,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(data.length, (i) {
                        final net = data[i].income - data[i].expenses;
                        return FlSpot(i.toDouble(), net);
                      }),
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: _netColor(),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, xPercentage, bar, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: spot.y >= 0
                                  ? AppColors.success
                                  : AppColors.danger,
                              strokeWidth: 2,
                              strokeColor: context.tokens.surface,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            _netColor().withValues(alpha: 0.2),
                            _netColor().withValues(alpha: 0.02),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                  minY: _minY(),
                  maxY: _maxY(),
                ),
                duration: const Duration(milliseconds: 400),
              ),
            ),
        ],
      ),
    );
  }

  Color _netColor() {
    final totalNet = data.fold<double>(
      0,
      (sum, d) => sum + d.income - d.expenses,
    );
    return totalNet >= 0 ? AppColors.success : AppColors.danger;
  }

  double _minY() {
    double min = 0;
    for (final d in data) {
      final net = d.income - d.expenses;
      if (net < min) min = net;
    }
    return min == 0 ? -100 : min * 1.2;
  }

  double _maxY() {
    double max = 0;
    for (final d in data) {
      final net = d.income - d.expenses;
      if (net > max) max = net;
    }
    return max == 0 ? 100 : max * 1.2;
  }

  double _interval() {
    final range = _maxY() - _minY();
    if (range == 0) return 50;
    return range / 4;
  }

  String _formatCompact(double value) {
    return Formatters.compactNumber(value, locale: locale);
  }
}
