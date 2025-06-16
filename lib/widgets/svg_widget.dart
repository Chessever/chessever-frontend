import 'package:chessever2/widgets/icons/analysis_board_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SvgWidget extends StatelessWidget {
  const SvgWidget(
    this.path, {
    this.height = 20.0,
    this.width = 20.0,
    this.semanticsLabel,
    this.colorFilter,
    this.fallback,
    super.key,
  });

  final String path;
  final double height;
  final double width;
  final String? semanticsLabel;
  final ColorFilter? colorFilter;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      path,
      semanticsLabel: semanticsLabel,
      height: height,
      width: width,
      colorFilter: colorFilter,
      errorBuilder:
          (context, obj, _) => fallback ?? AnalysisBoardIcon(size: height),
    );
  }
}
