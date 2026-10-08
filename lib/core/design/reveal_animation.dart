import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design_tokens.dart';

/// Fade + 14px slide-up entrance; [index] adds a 50ms stagger.
/// Items past index 10 appear immediately. Respects
/// `MediaQuery.disableAnimations`.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.distance = 14,
  });

  final Widget child;
  final int index;
  final Duration delay;
  final double distance;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DesignTokens.normal,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: DesignTokens.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DesignTokens.animationsOff(context) || widget.index > 10) {
      _c.value = 1;
      return;
    }
    final d = widget.delay + DesignTokens.stagger * widget.index;
    if (d == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(d, () {
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
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * widget.distance),
          child: child,
        ),
      ),
    );
  }
}
