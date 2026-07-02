import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/widgets/ds/build_card.dart';
import 'package:flutter/material.dart';

/// Compact stat tile: an icon + label row above a large value. Used in the home
/// two-up grid (Active projects, Budget health).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.valueColor,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BuildCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor ?? t.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: valueColor ?? t.text,
            ),
          ),
        ],
      ),
    );
  }
}
