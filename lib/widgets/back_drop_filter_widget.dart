import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The dim behind a sheet: the palette's radial vignette, and nothing else.
///
/// It used to blur the whole screen under it as well (sigma 15), which made
/// the GPU re-blur the entire page on every frame anything moved. The
/// vignette alone carries the dim; a frost belongs on a panel, cut to its
/// size ([PopupGlass]), never on the full screen. The name is kept for its
/// callers.
class BackDropFilterWidget extends StatelessWidget {
  const BackDropFilterWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          // Paper dims with the palette's ink; a black wash turns it grey.
          gradient: context.isLightTheme
              ? radialOverlayGradientLight
              : radialOverlayGradient,
        ),
      ),
    );
  }
}
