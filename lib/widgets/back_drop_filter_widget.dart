import 'dart:ui';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class BackDropFilterWidget extends StatelessWidget {
  const BackDropFilterWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: BackdropFilter(
        blendMode: BlendMode.luminosity,
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(gradient: radialOverlayGradient),
        ),
      ),
    );
  }
}
