import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design_tokens.dart';

/// Animates a number from 0 to [value] (and between later values).
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
    this.duration = const Duration(milliseconds: 900),
  });

  final num value;
  final TextStyle? style;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (DesignTokens.animationsOff(context)) {
      return Text('${value.round()}$suffix', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: DesignTokens.curve,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}
