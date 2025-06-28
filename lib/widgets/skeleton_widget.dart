import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class SkeletonWidget extends StatelessWidget {
  const SkeletonWidget({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      ignorePointers: true,
      effect: ShimmerEffect(
        baseColor: kBlackColor,
        highlightColor: kDarkGreyColor,
      ),
      child: child,
    );
  }
}
