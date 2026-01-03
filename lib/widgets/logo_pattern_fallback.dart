import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';

/// A fallback widget that displays the app logo in a beautiful repeating pattern.
/// Use this instead of placeholder icons when no image is available.
class LogoPatternFallback extends StatelessWidget {
  const LogoPatternFallback({
    super.key,
    this.logoSize = 32.0,
    this.opacity = 0.12,
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
    final pattern = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: borderRadius,
      ),
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            image: DecorationImage(
              image: const AssetImage(PngAsset.newAppLogo),
              repeat: ImageRepeat.repeat,
              scale: 4.0 / (logoSize / 32.0), // Adjust scale based on desired logo size
              colorFilter: const ColorFilter.mode(
                kWhiteColor,
                BlendMode.srcIn,
              ),
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: pattern,
      );
    }

    return pattern;
  }
}
