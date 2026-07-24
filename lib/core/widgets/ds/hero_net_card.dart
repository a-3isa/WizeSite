import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/widgets/ds/animated_counter.dart';
import 'package:buildtrack_app/core/widgets/ds/build_card.dart';
import 'package:buildtrack_app/core/widgets/ds/segmented_toggle.dart';
import 'package:flutter/material.dart';

enum HeroPeriod { week, month }

/// The home hero: "Net this month" label + Week/Month segmented control, a large
/// net figure with a trend icon and currency, and an income / expense split.
/// Numeric strings are passed pre-formatted (thousands-separated) by the caller.
class HeroNetCard extends StatelessWidget {
  const HeroNetCard({
    required this.title,
    required this.net,
    required this.income,
    required this.expense,
    required this.incomeLabel,
    required this.expenseLabel,
    this.currency = 'EGP',
    this.negative = false,
    this.period = HeroPeriod.month,
    this.weekLabel = 'Week',
    this.monthLabel = 'Month',
    this.onPeriodChanged,
    super.key,
  });

  final String title;
  final String net;
  final String income;
  final String expense;
  final String incomeLabel;
  final String expenseLabel;
  final String currency;
  final bool negative;
  final HeroPeriod period;
  final String weekLabel;
  final String monthLabel;
  final ValueChanged<HeroPeriod>? onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BuildCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
              ),
              if (onPeriodChanged != null)
                SegmentedToggle<HeroPeriod>(
                  value: period,
                  onChanged: onPeriodChanged!,
                  options: [
                    SegmentedOption(value: HeroPeriod.week, label: weekLabel),
                    SegmentedOption(value: HeroPeriod.month, label: monthLabel),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(
                negative ? Icons.trending_down : Icons.trending_up,
                size: 26,
                color: negative ? t.expense : t.income,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: AnimatedCounter(
                  net,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currency,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SplitBox(
                  label: incomeLabel,
                  value: income,
                  bg: t.incomeSoft,
                  fg: t.income,
                  radius: t.rMd,
                  mutedColor: t.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SplitBox(
                  label: expenseLabel,
                  value: expense,
                  bg: t.expenseSoft,
                  fg: t.expense,
                  radius: t.rMd,
                  mutedColor: t.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SplitBox extends StatelessWidget {
  const _SplitBox({
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    required this.radius,
    required this.mutedColor,
  });

  final String label;
  final String value;
  final Color bg;
  final Color fg;
  final double radius;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: mutedColor)),
          const SizedBox(height: 2),
          AnimatedCounter(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
