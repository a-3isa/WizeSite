import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:flutter/material.dart';

/// Circular initials avatar on an accent-soft background.
class Avatar extends StatelessWidget {
  const Avatar({required this.label, this.size = 40, super.key});

  final String label;
  final double size;

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p.characters.first).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: TextStyle(
          color: t.accent,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
