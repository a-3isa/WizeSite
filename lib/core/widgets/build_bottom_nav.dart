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

/// Height of the nav content (excluding the bottom safe-area inset).
const double kBuildBottomNavHeight = 62;

/// v2 bottom navigation: four fixed-height tabs with a central gap for the
/// docked add FAB (see [BuildAddFab] + `FloatingActionButtonLocation.centerDocked`).
/// Active tabs fill their icon and take the accent color; the bar casts an
/// upward shadow. The bar's height is fixed so the Scaffold body keeps its
/// full size (an unconstrained child here would swallow the whole screen).
class BuildBottomNav extends StatelessWidget {
  const BuildBottomNav({
    required this.currentIndex,
    required this.items,
    required this.onSelect,
    super.key,
  }) : assert(items.length == 4, 'BuildBottomNav expects exactly 4 items');

  final int currentIndex;
  final List<BuildNavItem> items;
  final ValueChanged<int> onSelect;

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
        child: SizedBox(
          height: kBuildBottomNavHeight,
          child: Row(
            children: [
              _tab(context, 0),
              _tab(context, 1),
              // Central gap the docked FAB floats over.
              const SizedBox(width: 76),
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
      child: Semantics(
        button: true,
        selected: on,
        label: item.label,
        child: InkWell(
          onTap: () => onSelect(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                on ? item.activeIcon : item.icon,
                size: 24,
                color: color,
                key: item.key,
              ),
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

/// The raised orange add button docked over the bottom nav's central gap.
/// Use with `Scaffold.floatingActionButton` +
/// `FloatingActionButtonLocation.centerDocked`.
class BuildAddFab extends StatelessWidget {
  const BuildAddFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // ~12% smaller than the original 58px diameter (UI audit problems 9/29:
    // the raised FAB was oversized and dominated the nav). Still comfortably
    // above Android's 48dp minimum touch target.
    return SizedBox(
      width: 52,
      height: 52,
      child: Material(
        color: t.accent,
        borderRadius: BorderRadius.circular(18),
        elevation: 6,
        shadowColor: t.accent.withValues(alpha: 0.45),
        child: InkWell(
          key: const Key('qa_nav_add'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Icon(Icons.add, size: 27, color: t.onAccent),
        ),
      ),
    );
  }
}
