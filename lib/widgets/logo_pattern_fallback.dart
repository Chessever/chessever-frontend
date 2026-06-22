import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';

/// Fallback image shown when no event/broadcast artwork is available.
/// A single, centered ChessEver logo on its dark backdrop — NOT a repeating
/// tile (the old tiled pattern looked busy/ugly at card sizes).
class LogoPatternFallback extends StatelessWidget {
  const LogoPatternFallback({
    super.key,
    this.logoSize = 32.0,
    this.opacity = 1.0,
    this.borderRadius,
  });

  /// Retained for call-site compatibility; no longer affects the layout.
  final double logoSize;

  /// Opacity of the logo (0.0 to 1.0).
  final double opacity;

  /// Optional border radius for clipping.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    // The logo art sits on black; covering the box edge-to-edge keeps the
    // backdrop seamless while showing a single centered mark.
    final image = ColoredBox(
      color: Colors.black,
      child: Opacity(
        opacity: opacity,
        child: Image.asset(PngAsset.newAppLogo, fit: BoxFit.cover),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
