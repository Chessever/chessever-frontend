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
        baseColor: kBlackColor,
        highlightColor: kDarkGreyColor,
      ),
      child: child,
    );
  }
}
