import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// A destination in [BuildBottomNav].
class BuildNavItem {
  const BuildNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.key,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Key? key;
}

/// v2 bottom navigation: five slots with a raised center "+" FAB. Active tabs
/// fill their icon and take the accent color; the bar casts an upward shadow.
///
/// [currentIndex] is the selected *branch* index (0-based, excluding the center
/// add button). [items] must contain exactly four entries — two before and two
/// after the center button.
class BuildBottomNav extends StatelessWidget {
  const BuildBottomNav({
    required this.currentIndex,
    required this.items,
    required this.onSelect,
    required this.onAdd,
    this.addKey,
    super.key,
  }) : assert(items.length == 4, 'BuildBottomNav expects exactly 4 items');

  final int currentIndex;
  final List<BuildNavItem> items;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final Key? addKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
        boxShadow: t.shadowNav,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _tab(context, 0),
              _tab(context, 1),
              _AddButton(onTap: onAdd, addKey: addKey, tokens: t),
              _tab(context, 2),
              _tab(context, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int index) {
    final t = context.tokens;
    final item = items[index];
    final on = index == currentIndex;
    final color = on ? t.accent : t.textFaint;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(index),
        borderRadius: BorderRadius.circular(t.rMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? item.activeIcon : item.icon, size: 24, color: color, key: item.key),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.tokens, this.addKey});

  final VoidCallback onTap;
  final BuildTokens tokens;
  final Key? addKey;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Align(
        alignment: Alignment.topCenter,
        child: Transform.translate(
          offset: const Offset(0, -18),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              key: addKey,
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: tokens.accent.withValues(alpha: 0.45),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.add, size: 30, color: tokens.onAccent),
            ),
          ),
        ),
      ),
    );
  }
}
