import 'package:flutter/material.dart';

/// A rounded, determinate [LinearProgressIndicator] that fills in smoothly
/// from zero (or its previous rendered fraction) to [value] instead of
/// popping in already at its target width -- the "progress bar animation"
/// called out by the v2 UI audit's Interaction Improvements section. Used
/// for budget-used bars and project-timeline elapsed bars.
///
/// [value] is a fraction in `[0, 1]`; values outside that range are clamped.
///
/// Respects reduced-motion: when `MediaQuery.of(context).disableAnimations`
/// is true, the bar renders at its target fraction immediately with no
/// animation.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.minHeight = 8,
    this.borderRadius = 4,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutCubic,
    super.key,
  });

  final double value;
  final Color color;
  final Color backgroundColor;
  final double minHeight;
  final double borderRadius;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget bar(double v) => LinearProgressIndicator(
      value: v,
      minHeight: minHeight,
      backgroundColor: backgroundColor,
      valueColor: AlwaysStoppedAnimation<Color>(color),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: reduceMotion
          ? bar(target)
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: target),
              duration: duration,
              curve: curve,
              builder: (context, animated, child) => bar(animated),
            ),
    );
  }
}
