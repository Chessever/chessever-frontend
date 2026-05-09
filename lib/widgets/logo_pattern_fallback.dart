import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A fallback widget that displays the app logo in a beautiful repeating pattern.
/// Use this instead of placeholder icons when no image is available.
class LogoPatternFallback extends StatelessWidget {
  const LogoPatternFallback({
    super.key,
    this.logoSize = 32.0,
    this.opacity = 1.0,
    this.borderRadius,
  });

  /// Size of each logo in the pattern
  final double logoSize;

  /// Opacity of the logos (0.0 to 1.0)
  final double opacity;

  /// Optional border radius for clipping
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final divisor = logoSize / 32.0;
    final scale = divisor > 0 && divisor.isFinite ? 4.0 / divisor : 4.0;

    final pattern = Container(
      decoration: BoxDecoration(
        gradient:  LinearGradient(
          colors: [context.colors.surface, Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadius,
      ),
      child: Opacity(
        opacity: opacity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
              return const SizedBox.expand();
            }
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                image: DecorationImage(
                  image: const AssetImage(PngAsset.premium2Icon),
                  repeat: ImageRepeat.repeat,
                  scale: scale,
                ),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: pattern);
    }

    return pattern;
  }
}
