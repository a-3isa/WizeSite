import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// Labelled text field matching the v2 `Field` primitive: label above, rounded
/// bordered input that shows a 2px accent border on focus.
class BuildTextField extends StatelessWidget {
  const BuildTextField({
    required this.label,
    this.controller,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.onChanged,
    this.inputFormatters,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final List<dynamic>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            suffixText: suffixText,
          ),
        ),
      ],
    );
  }
}

/// Simple rounded progress bar (budget usage). [value] is 0..1.
class BuildProgress extends StatelessWidget {
  const BuildProgress({
    required this.value,
    this.color,
    this.height = 8,
    super.key,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: t.surface3,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? t.accent),
      ),
    );
  }
}
