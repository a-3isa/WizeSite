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
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  title: Text(
                    option.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  trailing: option.value == selected
                      ? Icon(Icons.check, color: t.accent)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.value),
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
