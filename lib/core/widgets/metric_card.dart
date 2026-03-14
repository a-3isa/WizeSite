import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    this.color = AppColors.textDark,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Generate a very light background tint based on the brand color
    final bool isBrandColor =
        color == AppColors.constructionOrange ||
        color == AppColors.success ||
        color == AppColors.danger;
    final Color bgColor = isBrandColor
        ? color.withValues(alpha: 0.1)
        : AppColors.surfaceSolid;
    final Color borderColor = isBrandColor
        ? color.withValues(alpha: 0.2)
        : AppColors.borderGrey;
    final Color iconColor = color;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textBody,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isBrandColor)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon ?? Icons.bar_chart,
                    color: iconColor,
                    size: 16,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
