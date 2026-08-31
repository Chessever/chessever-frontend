import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

/// Canonical icon for every entry point that opens the shared Board workspace.
class BoardNavigationIcon extends StatelessWidget {
  const BoardNavigationIcon({
    required this.size,
    this.semanticsLabel = 'Board',
    super.key,
  });

  final double size;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgWidget(
      SvgAsset.analysisBoard,
      semanticsLabel: semanticsLabel,
      width: size,
      height: size,
      preserveOriginalColors: true,
    );
  }
}
