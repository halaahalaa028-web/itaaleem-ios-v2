import 'package:flutter/material.dart';

/// Widest a content column gets on a tablet (iPad) — beyond it the content
/// is centered instead of stretching across the whole screen.
const kMaxContentWidth = 720.0;

/// Centers [child] at most [maxWidth] wide. A no-op on phones (narrower
/// than [maxWidth]), so phone layouts are unchanged.
class ContentWidthLimit extends StatelessWidget {
  const ContentWidthLimit({
    super.key,
    required this.child,
    this.maxWidth = kMaxContentWidth,
  }) : page = false;

  /// For a whole routed screen (its own Scaffold): paints the theme's
  /// background on either side of the centered column.
  const ContentWidthLimit.page({
    super.key,
    required this.child,
    this.maxWidth = kMaxContentWidth,
  }) : page = true;

  final Widget child;
  final double maxWidth;
  final bool page;

  @override
  Widget build(BuildContext context) {
    if (page) {
      if (MediaQuery.sizeOf(context).width <= maxWidth) return child;
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
