import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Local 768px artwork with no network dependency or animated loading swap.
/// Study scenes keep their scale and fade their own pixels clear of the label.
class HubIllustration extends StatelessWidget {
  const HubIllustration({
    super.key,
    required this.asset,
    this.alignment = Alignment.topCenter,
    this.framed = false,
  });

  final String asset;
  final Alignment alignment;

  /// Fits a wide study scene above the text rather than enlarging it to cover.
  final bool framed;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Opacity(
        opacity: context.isLightTheme ? .32 : 1,
        child: framed
            ? LayoutBuilder(
                builder: (context, constraints) {
                  // Both study sources are 3:1. Only their quiet left field
                  // can extend beyond a compact card; the subjects keep the
                  // same size and top-right position in either card format.
                  final height = 80.sp.clamp(0.0, constraints.maxHeight);
                  final width = height * 3;
                  return ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topRight,
                      minWidth: width,
                      maxWidth: width,
                      minHeight: height,
                      maxHeight: height,
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0, 0.6, 1],
                        ).createShader(bounds),
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          // A full-row card exposes the source's left edge.
                          // Fade those pixels before the subjects begin so
                          // neither theme shows a rectangular image seam.
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Colors.transparent,
                              Color(0x08ffffff),
                              Color(0x24ffffff),
                              Color(0x51ffffff),
                              Color(0x88ffffff),
                              Color(0xbaffffff),
                              Color(0xe1ffffff),
                              Color(0xf8ffffff),
                              Colors.white,
                              Colors.white,
                            ],
                            stops: [0, .05, .1, .15, .2, .25, .3, .35, .4, 1],
                          ).createShader(bounds),
                          child: Image.asset(
                            asset,
                            width: width,
                            height: height,
                            fit: BoxFit.contain,
                            cacheWidth: 768,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              )
            : Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: alignment,
                cacheWidth: 768,
                filterQuality: FilterQuality.medium,
              ),
      ),
    ),
  );
}
