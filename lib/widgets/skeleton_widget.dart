import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class SkeletonWidget extends StatelessWidget {
  const SkeletonWidget({
    required this.child,
    this.ignoreContainers = false,
    super.key,
  });

  final Widget child;
  final bool ignoreContainers;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      ignoreContainers: true,
      ignorePointers: true,
      effect: ShimmerEffect(
        // Dark theme keeps the original kBlackColor base; light theme swaps
        // to a theme-aware skeleton tone so the shimmer doesn't paint as a
        // black smear on white surfaces.
        baseColor: context.isLightTheme ? context.colors.skeleton : kBlackColor,
        highlightColor: context.colors.surfaceRecessed,
      ),
      child: child,
    );
  }
}
