import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

/// SVG icon that picks up [IconTheme] color from [GlassTabBar] / glass controls.
class GlassNavIcon extends StatelessWidget {
  const GlassNavIcon(
    this.assetPath, {
    this.size = 22,
    super.key,
  });

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = theme.color ?? DefaultTextStyle.of(context).style.color;
    return SvgWidget(
      assetPath,
      height: size,
      width: size,
      colorFilter:
          color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null,
    );
  }
}
