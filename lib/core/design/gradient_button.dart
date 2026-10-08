import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design_tokens.dart';
import 'package:itaaleem/core/design/pressable_scale.dart';

/// Primary CTA filled with the brand gradient (primary → secondary).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !loading;
    final br = BorderRadius.circular(DesignTokens.radiusButton);
    final text = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: s.onPrimary,
      fontWeight: FontWeight.w700,
    );

    return PressableScale(
      enabled: enabled,
      child: AnimatedOpacity(
        duration: DesignTokens.fast,
        opacity: onPressed == null && !loading ? 0.5 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: DesignTokens.brandGradient(s),
            borderRadius: br,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: s.primary.withValues(alpha: 0.32),
                      blurRadius: 20,
                      spreadRadius: -6,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: br,
            child: InkWell(
              borderRadius: br,
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                height: height,
                width: expand ? double.infinity : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    widthFactor: 1,
                    child: loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: s.onPrimary,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(icon, color: s.onPrimary, size: 20),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  style: text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
