import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// Pill chip used for quick-add actions and filter toggles. When [active] it
/// takes the accent-soft background + accent border/label.
class BuildChip extends StatelessWidget {
  const BuildChip({
    required this.label,
    this.icon,
    this.dotColor,
    this.active = false,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? dotColor;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: active ? t.accentSoft : t.surface,
      borderRadius: BorderRadius.circular(BuildTokens.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BuildTokens.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BuildTokens.pill),
            border: Border.all(
              color: active ? t.accent : t.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: active ? t.accent : t.textMuted,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? t.accent : t.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
