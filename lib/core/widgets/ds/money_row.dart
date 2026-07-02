import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

enum MoneyKind { income, expense }

/// A transaction row: tinted icon badge, title + subtitle, signed amount and a
/// trailing currency code. Green for income/funds-in, red for expense.
class MoneyRow extends StatelessWidget {
  const MoneyRow({
    required this.title,
    required this.amount,
    this.subtitle,
    this.kind = MoneyKind.expense,
    this.icon,
    this.currency = 'EGP',
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final String title;
  final String amount;
  final String? subtitle;
  final MoneyKind kind;
  final IconData? icon;
  final String currency;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final income = kind == MoneyKind.income;
    final color = income ? t.income : t.expense;
    final soft = income ? t.incomeSoft : t.expenseSoft;
    final glyph = icon ?? (income ? Icons.south_west : Icons.north_east);
    final sign = income ? '+' : '−';

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(glyph, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: t.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign$amount',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 1),
              Text(currency, style: TextStyle(fontSize: 11, color: t.textFaint)),
            ],
          ),
        ],
      ),
    );

    final content = onTap == null
        ? row
        : InkWell(onTap: onTap, child: row);

    if (!showDivider) return content;
    return Column(
      children: [
        content,
        Divider(height: 1, thickness: 1, color: t.border),
      ],
    );
  }
}
