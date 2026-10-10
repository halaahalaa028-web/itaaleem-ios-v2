import 'package:flutter/material.dart';
import 'package:itaaleem/core/theme/app_colors.dart';

/// Living background for the main screens: large soft brand-tinted blobs
/// plus a very faint grid, painted once inside a [RepaintBoundary]. Blobs are
/// radial gradients (no BackdropFilter), so they cost a single cached paint.
/// Not for the video player or the PDF viewer.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.showGrid = true});

  final Widget child;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    // Always fills the available space (never just the content's height),
    // so short screens don't leave an unpainted strip below the content.
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ColoredBox(color: AppColors.backgroundFor(s.brightness)),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BackgroundPainter(
                  primary: s.primary,
                  secondary: s.secondary,
                  tertiary: s.tertiary,
                  grid: showGrid ? s.onSurface : null,
                  dark: s.brightness == Brightness.dark,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.grid,
    required this.dark,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color? grid;
  final bool dark;

  void _blob(Canvas canvas, Offset c, double r, Color color, double alpha) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final a = dark ? 0.15 : 0.11;
    _blob(canvas, Offset(w * 0.95, h * 0.04), w * 0.75, primary, a);
    _blob(canvas, Offset(w * 0.02, h * 0.38), w * 0.65, secondary, a * 0.8);
    _blob(canvas, Offset(w * 0.85, h * 0.92), w * 0.7, tertiary, a * 0.7);

    final g = grid;
    if (g == null) return;
    final line = Paint()
      ..color = g.withValues(alpha: dark ? 0.035 : 0.03)
      ..strokeWidth = 1;
    const step = 32.0;
    for (var x = 0.0; x < w; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), line);
    }
    for (var y = 0.0; y < h; y += step) {
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.primary != primary ||
      old.secondary != secondary ||
      old.tertiary != tertiary ||
      old.grid != grid ||
      old.dark != dark;
}
