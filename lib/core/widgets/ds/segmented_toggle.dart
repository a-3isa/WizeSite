import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

class SegmentedOption<T> {
  const SegmentedOption({required this.value, required this.label});
  final T value;
  final String label;
}

/// Pill segmented control (e.g. Week / Month, EN / ع). The selected segment
/// lifts onto a `surface` chip with a soft shadow.
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<SegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(BuildTokens.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final on = o.value == value;
          return GestureDetector(
            onTap: () => onChanged(o.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: on ? t.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(BuildTokens.pill),
                boxShadow: on ? t.shadowSm : null,
              ),
              child: Text(
                o.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? t.text : t.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
