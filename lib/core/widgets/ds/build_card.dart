import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// A v2 surface card: token surface color, hairline border, rounded corners and
/// a soft house shadow (stronger when [elevated]).
class BuildCard extends StatelessWidget {
  const BuildCard({
    required this.child,
    this.padding,
    this.elevated = false,
    this.onTap,
    this.color,
    this.margin,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool elevated;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.rLg);
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: radius,
        border: Border.all(color: t.border),
        boxShadow: elevated ? t.shadowMd : t.shadowSm,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(t.cardPad),
        child: child,
      ),
    );

    if (onTap == null) {
      return Container(margin: margin, child: decorated);
    }
    return Container(
      margin: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: decorated,
        ),
      ),
    );
  }
}
