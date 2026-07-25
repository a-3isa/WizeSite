import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// A single option shown in the [pickOption] bottom sheet: a stored `value`
/// paired with the label rendered for it.
typedef PickerOption<T> = ({T value, String label});

/// Shows a bottom-sheet list of [options] and invokes [onSelected] with the
/// tapped option's `value`. Backs the picker affordance used behind
/// [SelectField]s (project / category / payment-method selection, etc.)
/// across the add-expense, add-payment, and voice-review screens.
Future<void> pickOption<T>(
  BuildContext context, {
  required String title,
  required T? selected,
  required List<PickerOption<T>> options,
  required ValueChanged<T> onSelected,
}) async {
  final t = context.tokens;
  final result = await showModalBottomSheet<T>(
    context: context,
    backgroundColor: t.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.rLg)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle — signals the sheet is dismissable and visually
              // caps the header off from the option rows below.
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.borderStrong,
                  borderRadius: BorderRadius.circular(BuildTokens.pill),
                ),
              ),
              // Header: deliberately styled unlike the option rows (larger,
              // heavier, muted-uppercase eyebrow context, and a divider under
              // it) so the sheet title never reads as a selectable option.
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 2, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: t.text,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: t.border),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final option in options)
                      _OptionTile<T>(
                        label: option.label,
                        selected: option.value == selected,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(option.value),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
  if (result != null) {
    onSelected(result);
  }
}

/// A single selectable row in the [pickOption] sheet. The selected row is
/// tinted and accent-colored with a check, so options read clearly as choices
/// distinct from the bold sheet header above.
class _OptionTile<T> extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: selected ? t.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? t.accent : t.text,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 20, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}
