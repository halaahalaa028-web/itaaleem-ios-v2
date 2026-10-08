import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted app bar (BackdropFilter + translucent surface). Pair with
/// `Scaffold(extendBodyBehindAppBar: true)` on screens with `AppBackground`.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(60 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AppBar(
          title: title,
          actions: actions,
          leading: leading,
          bottom: bottom,
          automaticallyImplyLeading: automaticallyImplyLeading,
          backgroundColor: s.surface.withValues(alpha: 0.7),
          scrolledUnderElevation: 0,
          shape: Border(
            bottom: BorderSide(color: s.outlineVariant.withValues(alpha: 0.25)),
          ),
        ),
      ),
    );
  }
}
