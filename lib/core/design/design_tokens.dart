import 'package:flutter/material.dart';

/// Design tokens of the visual language shared with itaaleem.com: big soft
/// radii, diffuse shadows, brand gradients built from the active scheme.
/// Everything derives from [ColorScheme] so center colors and dark mode
/// re-tint it automatically.
class DesignTokens {
  DesignTokens._();

  static const double radiusCard = 22;
  static const double radiusHero = 24;
  static const double radiusButton = 16;

  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration stagger = Duration(milliseconds: 50);
  static const Curve curve = Curves.easeOutCubic;

  /// Primary → secondary brand gradient for featured cards and CTAs.
  static LinearGradient brandGradient(ColorScheme s) => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [s.primary, Color.lerp(s.primary, s.secondary, 0.75)!],
  );

  /// Soft diffuse shadow (not hard). Tinted by the brand in light mode.
  static List<BoxShadow> softShadow(ColorScheme s, {double strength = 1}) {
    final dark = s.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: (dark ? Colors.black : s.primary).withValues(
          alpha: (dark ? 0.28 : 0.07) * strength,
        ),
        blurRadius: 28,
        spreadRadius: -4,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: s.shadow.withValues(alpha: (dark ? 0.18 : 0.03) * strength),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Thin border: translucent in dark mode, hairline in light.
  static Color cardBorder(ColorScheme s) => s.brightness == Brightness.dark
      ? s.onSurface.withValues(alpha: 0.08)
      : s.outlineVariant.withValues(alpha: 0.45);

  static bool animationsOff(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
