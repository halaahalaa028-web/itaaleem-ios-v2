import 'package:flutter/material.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';

/// A single shimmering placeholder box. For lists use the existing
/// [ShimmerList] / [ShimmerCard] from app_shimmer.dart (re-exported by the
/// design barrel), which share one AnimationController per skeleton.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 12,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => AppShimmer(
    child: ShimmerBlock(width: width, height: height, radius: radius),
  );
}
