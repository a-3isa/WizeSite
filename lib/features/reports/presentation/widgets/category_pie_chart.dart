import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/utils/formatters.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class CategoryPieChart extends StatefulWidget {
  const CategoryPieChart({
    required this.data,
    required this.currency,
    required this.locale,
    super.key,
  });

  final Map<String, double> data;
  final String currency;
  final String locale;

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int _touchedIndex = -1;

  static const _categoryColors = <String, Color>{
    'labor': AppColors.constructionOrange,
    'materials': Color(0xFF3B82F6),
    'equipment': Color(0xFFF59E0B),
    'transport': Color(0xFF14B8A6),
    'other': Color(0xFF94A3B8),
  };

  Color _colorFor(String category) =>
      _categoryColors[category] ?? const Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = widget.data.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) {
      return _EmptyChartCard(label: l10n.t('noDataYet'));
    }

    final entries = widget.data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
            l10n.t('expenseBreakdown'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.tokens.text,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sectionsSpace: 3,
                centerSpaceRadius: 50,
                sections: List.generate(entries.length, (i) {
                  final isTouched = i == _touchedIndex;
                  final entry = entries[i];
                  final percentage = (entry.value / total * 100);
                  return PieChartSectionData(
                    value: entry.value,
                    color: _colorFor(entry.key),
                    radius: isTouched ? 60 : 50,
                    title: '${percentage.toStringAsFixed(0)}%',
                    titleStyle: TextStyle(
                      fontSize: isTouched ? 14 : 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    titlePositionPercentageOffset: 0.6,
                  );
                }),
              ),
              duration: const Duration(milliseconds: 300),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: entries.map((entry) {
              return _LegendItem(
                color: _colorFor(entry.key),
                label: l10n.expenseCategoryLabel(entry.key),
                value: Formatters.money(
                  entry.value,
                  currencyCode: widget.currency,
                  locale: widget.locale,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($value)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.tokens.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _EmptyChartCard extends StatelessWidget {
  const _EmptyChartCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.tokens.border),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.tokens.textMuted),
        ),
      ),
    );
  }
}
