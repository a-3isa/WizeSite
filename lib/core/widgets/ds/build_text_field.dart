import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Labelled text field matching the v2 `Field` primitive: label above, rounded
/// bordered input that shows a 2px accent border on focus.
///
/// When [obscureText] is set the field manages its own show/hide toggle, so
/// password inputs get a reveal affordance without every caller rebuilding it.
class BuildTextField extends StatefulWidget {
  const BuildTextField({
    required this.label,
    this.controller,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.obscureText = false,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.errorText,
    this.maxLines = 1,
    this.fieldKey,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final String? errorText;

  /// Number of lines for the underlying [TextField] (defaults to 1). Ignored
  /// while [obscureText] is set, matching [TextField]'s own behavior.
  final int maxLines;

  /// Optional key applied directly to the inner [TextField] so tests can
  /// target the editable widget without depending on label placement.
  final Key? fieldKey;

  @override
  State<BuildTextField> createState() => _BuildTextFieldState();
}

class _BuildTextFieldState extends State<BuildTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 7),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
        ),
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          inputFormatters: widget.inputFormatters,
          obscureText: _obscured,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          enabled: widget.enabled,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            suffixText: widget.suffixText,
            errorText: widget.errorText,
            suffixIcon: widget.obscureText
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: t.textMuted,
                    ),
                  )
                : null,
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

/// Shared color-grading rule for budget/usage progress bars: green while
/// spending is comfortably under budget, amber as it approaches the limit,
/// red once it's close to or over budget.
///
/// [usedFraction] is `spent / budgetBase` (not clamped by the caller is
/// fine — anything at or above 1.0 already falls in the red band). Every
/// budget-progress call site (project list cards, project detail hero,
/// project-scoped dashboard section) should call this instead of rolling
/// its own thresholds so the color language stays consistent app-wide.
Color budgetProgressColor(BuildTokens t, double usedFraction) {
  if (usedFraction >= 0.9) return t.expense;
  if (usedFraction >= 0.7) return t.warning;
  return t.income;
}
