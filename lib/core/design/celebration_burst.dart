import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design_tokens.dart';

/// A light, one-shot confetti burst painted over [child] (no package). The
/// pieces use the scheme's primary / secondary / tertiary colors and fade
/// out within ~1.6s. Renders [child] alone when [active] is false or the
/// user turned animations off.
class CelebrationBurst extends StatefulWidget {
  const CelebrationBurst({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  State<CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<CelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final List<_Piece> _pieces;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _pieces = List.generate(36, (i) {
      final angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.4;
      return _Piece(
        angle: angle,
        speed: 0.55 + rnd.nextDouble() * 0.6,
        size: 4 + rnd.nextDouble() * 5,
        spin: (rnd.nextDouble() - 0.5) * 10,
        colorIndex: i % 3,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.active) return;
    _started = true;
    if (!DesignTokens.animationsOff(context)) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || DesignTokens.animationsOff(context)) {
      return widget.child;
    }
    final s = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _BurstPainter(
                    t: _c.value,
                    pieces: _pieces,
                    colors: [s.primary, s.secondary, s.tertiary],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.colorIndex,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final int colorIndex;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.pieces, required this.colors});

  final double t;
  final List<_Piece> pieces;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0 || t == 1) return;
    final center = size.center(Offset.zero);
    final reach = size.shortestSide * 0.9;
    final eased = Curves.easeOutCubic.transform(t);
    final opacity = (1 - t).clamp(0.0, 1.0);
    final paint = Paint();
    for (final p in pieces) {
      final d = reach * p.speed * eased;
      final gravity = 120 * t * t;
      final pos =
          center +
          Offset(math.cos(p.angle) * d, math.sin(p.angle) * d + gravity);
      paint.color = colors[p.colorIndex].withValues(alpha: opacity);
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(p.spin * t)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.55,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
