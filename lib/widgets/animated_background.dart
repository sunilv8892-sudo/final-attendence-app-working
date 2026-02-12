import 'package:flutter/material.dart';

/// AnimatedBackground provides a simple background with optional overlay
/// Optimized: uses ColoredBox instead of Container for lightweight rendering
class AnimatedBackground extends StatelessWidget {
  final Widget child;
  final bool isOverlay;

  const AnimatedBackground({super.key, required this.child, this.isOverlay = true});

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    if (!isOverlay) {
      return ColoredBox(color: surfaceColor, child: child);
    }
    return ColoredBox(
      color: surfaceColor,
      child: child,
    );
  }
}
