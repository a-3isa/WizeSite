import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// A tappable field that shows a label above and a value row that opens a picker
/// (project / category / method). Matches the v2 `SelectField`.
class SelectField extends StatelessWidget {
  const SelectField({
    required this.label,
    this.valueLabel,
    this.placeholder,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final String? valueLabel;
  final String? placeholder;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasValue = valueLabel != null && valueLabel!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
        ),
        Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.rMd),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(t.rMd),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.rMd),
                border: Border.all(color: t.borderStrong, width: 1.5),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: t.accent),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      hasValue ? valueLabel! : (placeholder ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: hasValue ? t.text : t.textFaint,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more, size: 22, color: t.textMuted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
