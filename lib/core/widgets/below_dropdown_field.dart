import 'package:flutter/material.dart';

class BelowDropdownField<T> extends StatelessWidget {
  const BelowDropdownField({
    required this.label,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
    this.menuHeight = 320,
    super.key,
  });

  final String label;
  final T? value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;
  final bool enabled;
  final double menuHeight;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T>(
      key: ValueKey<Object?>('${label}_$value'),
      enabled: enabled,
      initialSelection: value,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      enableSearch: false,
      menuHeight: menuHeight,
      menuStyle: const MenuStyle(alignment: AlignmentDirectional.bottomStart),
      dropdownMenuEntries: entries,
      onSelected: onSelected,
    );
  }
}
