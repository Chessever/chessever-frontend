import 'dart:ui';

import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';

class BackDropFilterWidget extends StatelessWidget {
  const BackDropFilterWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // NOTE: was BlendMode.luminosity. Luminosity blending keeps the
      // destination's chroma, so highly saturated content behind the dialog —
      // country flags especially — kept its full colour and appeared to
      // "punch through" the dim instead of being blacked out. The default
      // srcOver blend blurs and dims the whole backdrop uniformly, so flags
      // dim with everything else. The dark vignette in [radialOverlayGradient]
      // supplies the dim that the luminosity blend used to imply.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(gradient: radialOverlayGradient),
        ),
      ),
    );
  }
}
