import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/count_up_text.dart';
import 'package:itaaleem/core/design/design_tokens.dart';

/// Statistic tile: tinted icon, count-up number, label.
/// [onGradient] renders it light-on-brand for use inside a gradient card.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.onGradient = false,
    this.suffix = '',
  });

  final IconData icon;
  final num value;
  final String label;
  final Color? color;
  final bool onGradient;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final accent = color ?? s.primary;
    final fg = onGradient ? s.onPrimary : s.onSurface;
    final sub = onGradient
        ? s.onPrimary.withValues(alpha: 0.8)
        : s.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: onGradient ? s.onPrimary.withValues(alpha: 0.14) : s.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: onGradient
              ? s.onPrimary.withValues(alpha: 0.18)
              : DesignTokens.cardBorder(s),
        ),
        boxShadow: onGradient
            ? null
            : DesignTokens.softShadow(s, strength: 0.6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: onGradient
                  ? s.onPrimary.withValues(alpha: 0.18)
                  : accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: onGradient ? s.onPrimary : accent,
            ),
          ),
          const SizedBox(height: 8),
          CountUpText(
            value: value,
            suffix: suffix,
            style: t.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: fg,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.labelMedium?.copyWith(color: sub),
          ),
        ],
      ),
    );
  }
}
