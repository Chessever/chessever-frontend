import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';

/// The time-control marks (owl, rabbit, bolt), drawn for the theme.
///
/// The original PNGs are art for the dark stage: a white owl coin, a white
/// coin with a transparent rabbit cut-out, a #1389FD bolt. On paper the two
/// coins vanish and the bolt sits under 3:1, so light mode swaps in baked
/// twins (`*_light.png`: ink coins with a paper face, a #0F6ECA bolt). They
/// are plain asset swaps, so a long list pays no per-item filter layer.
///
/// Any other asset path passes through untouched, and dark renders the
/// originals exactly as before.
class TimeControlGlyph extends StatelessWidget {
  const TimeControlGlyph(
    this.asset, {
    super.key,
    required this.size,
    this.fit = BoxFit.contain,
    this.onDark,
    this.tint,
    this.semanticLabel,
  });

  /// One of [PngAsset.classicalIcon], [PngAsset.rapidIcon],
  /// [PngAsset.blitzIcon] (or the same raw `assets/pngs/*.png` strings).
  final String asset;

  /// Width and height of the square slot.
  final double size;

  final BoxFit fit;

  /// The ground the glyph actually sits on, when it is not the app theme's:
  /// `true` for a fixed-dark surface (a photo scrim, a dark share card) keeps
  /// the original art in light mode; `false` forces the paper twins. Null
  /// follows [Theme] brightness.
  final bool? onDark;

  /// Draws the glyph as a flat silhouette in this colour ([BlendMode.srcIn]),
  /// for marks sitting on an inverse fill such as an expanded ink header.
  final Color? tint;

  /// Announced label. Null keeps the glyph decorative (it usually sits beside
  /// its own text).
  final String? semanticLabel;

  static const Map<String, String> _lightTwins = {
    PngAsset.blitzIcon: PngAsset.blitzIconLight,
    PngAsset.classicalIcon: PngAsset.classicalIconLight,
    PngAsset.rapidIcon: PngAsset.rapidIconLight,
  };

  /// The asset to draw for [asset] on a [light] ground.
  static String resolve(String asset, {required bool light}) {
    if (!light) return asset;
    return _lightTwins[asset] ?? asset;
  }

  /// The glyph for a free-text time control ("Blitz", "rapid 15+10",
  /// "Standard"), or null when there is none (bullet has no mark).
  static String? assetForLabel(String? timeControl) {
    final t = (timeControl ?? '').toLowerCase();
    if (t.contains('blitz')) return PngAsset.blitzIcon;
    if (t.contains('rapid')) return PngAsset.rapidIcon;
    if (t.contains('classic') || t.contains('standard')) {
      return PngAsset.classicalIcon;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final light = onDark == null
        ? Theme.of(context).brightness == Brightness.light
        : !onDark!;
    // A silhouette only needs the alpha mask, which both sets share; the
    // original keeps the rabbit cut-out crisp either way.
    final resolved = tint != null ? asset : resolve(asset, light: light);
    return Image.asset(
      resolved,
      width: size,
      height: size,
      fit: fit,
      color: tint,
      colorBlendMode: tint == null ? null : BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
