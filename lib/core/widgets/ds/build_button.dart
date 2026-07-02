import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

enum BuildButtonVariant { primary, soft, outline, ghost, danger }

enum BuildButtonSize { sm, md, lg }

/// v2 button. Filled orange primary by default; soft/outline/ghost/danger
/// variants; three heights (sm 40 / md 50 / lg 56). Token-driven, dark-aware.
class BuildButton extends StatelessWidget {
  const BuildButton({
    required this.label,
    this.onPressed,
    this.variant = BuildButtonVariant.primary,
    this.size = BuildButtonSize.md,
    this.icon,
    this.iconRight,
    this.full = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BuildButtonVariant variant;
  final BuildButtonSize size;
  final IconData? icon;
  final IconData? iconRight;
  final bool full;

  double get _height => switch (size) {
    BuildButtonSize.sm => 40,
    BuildButtonSize.md => 50,
    BuildButtonSize.lg => 56,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (bg, fg, border) = switch (variant) {
      BuildButtonVariant.primary => (t.accent, t.onAccent, null),
      BuildButtonVariant.soft => (t.accentSoft, t.accent, null),
      BuildButtonVariant.outline => (t.surface, t.text, t.borderStrong),
      BuildButtonVariant.ghost => (Colors.transparent, t.text, null),
      BuildButtonVariant.danger => (t.expenseSoft, t.expense, null),
    };
    final disabled = onPressed == null;
    final fontSize = size == BuildButtonSize.sm ? 14.0 : 15.5;
    final iconSize = size == BuildButtonSize.sm ? 18.0 : 20.0;

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(t.rMd),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(t.rMd),
          child: Ink(
            height: _height,
            width: full ? double.infinity : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.rMd),
              border: border == null ? null : Border.all(color: border, width: 1.5),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: size == BuildButtonSize.sm ? 14 : 20,
            ),
            child: Row(
              mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: iconSize, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                    ),
                  ),
                ),
                if (iconRight != null) ...[
                  const SizedBox(width: 8),
                  Icon(iconRight, size: iconSize, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
