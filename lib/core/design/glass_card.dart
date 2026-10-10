import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design_tokens.dart';
import 'package:itaaleem/core/design/pressable_scale.dart';

/// Rounded surface card of the new language: 22px corners, diffuse shadow,
/// thin translucent border in dark mode. [gradient] makes it a featured
/// brand card. [blur] enables real glassmorphism — only for headers / single
/// hero cards (auth forms), never inside list items.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.color,
    this.radius = DesignTokens.radiusCard,
    this.blur = false,
    this.shadow = true,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final double radius;
  final bool blur;
  final bool shadow;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final br = BorderRadius.circular(radius);
    final fill =
        color ?? (blur ? s.surface.withValues(alpha: 0.72) : s.surface);

    Widget content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: br,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? fill : null,
            gradient: gradient,
            borderRadius: br,
            border: Border.all(
              color:
                  borderColor ??
                  (gradient != null
                      ? s.onPrimary.withValues(alpha: 0.14)
                      : DesignTokens.cardBorder(s)),
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    content = ClipRRect(
      borderRadius: br,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: content,
            )
          : content,
    );

    content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: shadow
            ? DesignTokens.softShadow(s, strength: gradient != null ? 1.6 : 1)
            : null,
      ),
      child: content,
    );

    return onTap == null ? content : PressableScale(child: content);
  }
}
