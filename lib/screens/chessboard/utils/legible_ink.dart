import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Hue-preserving ink for paper surfaces.
///
/// Board palettes (classification colours, NAG hues, like-tag swatches,
/// folder presets, variation depth tints) were tuned on black. Painted as
/// text on the light theme's mint paper most of them fall to 1.5–3.5:1.
/// These helpers keep the hue and saturation, so "the orange one" still
/// reads orange, and only darken the lightness until the ink clears WCAG.
///
/// Dark mode always gets the colour back untouched. Contrast is measured
/// with the theme's shared [wcagContrast] (lib/theme/app_colors.dart); every
/// caller here hands it an opaque surface.

/// [hue] as legible ink on the current surface. Dark returns [hue] as is.
///
/// [on] defaults to the theme background; pass the real surface when the
/// ink sits on a card or recessed well.
Color legibleHueInk(
  BuildContext context,
  Color hue, {
  double minContrast = 4.5,
  Color? on,
}) {
  if (!context.isLightTheme) return hue;
  return legibleHueInkOn(
    hue,
    on ?? context.colors.background,
    minContrast: minContrast,
  );
}

final Map<(int, int, double), Color> _inkCache = {};

/// Context-free core of [legibleHueInk]: lowers [hue]'s HSL lightness in
/// 0.01 steps until it reaches [minContrast] against [on]. The alpha of
/// [hue] is kept and taken into account (the ink is composited over [on]).
Color legibleHueInkOn(Color hue, Color on, {double minContrast = 4.5}) {
  final key = (hue.toARGB32(), on.toARGB32(), minContrast);
  final cached = _inkCache[key];
  if (cached != null) return cached;

  final alpha = hue.a;
  final solidOn = on.a < 1 ? Color.alphaBlend(on, Colors.white) : on;
  var hsl = HSLColor.fromColor(hue.withValues(alpha: 1));
  var ink = hsl.toColor().withValues(alpha: alpha);
  while (wcagContrast(ink, solidOn) < minContrast && hsl.lightness > 0) {
    hsl = hsl.withLightness((hsl.lightness - 0.01).clamp(0.0, 1.0));
    ink = hsl.toColor().withValues(alpha: alpha);
  }
  if (_inkCache.length > 512) _inkCache.clear();
  _inkCache[key] = ink;
  return ink;
}

/// Readable label ink for text drawn ON a [fill]. Dark returns [dark]
/// (white, the historic label colour). Light picks whichever of the theme
/// ink or white stands clearer of the fill.
Color labelOnFill(
  BuildContext context,
  Color fill, {
  Color dark = const Color(0xFFFFFFFF),
}) {
  if (!context.isLightTheme) return dark;
  final colors = context.colors;
  final solid = fill.a < 1 ? Color.alphaBlend(fill, colors.background) : fill;
  const white = Color(0xFFFFFFFF);
  return wcagContrast(colors.textPrimary, solid) >= wcagContrast(white, solid)
      ? colors.textPrimary
      : white;
}

/// Maps the pure-white fills and strokes of a dark-first SVG onto [ink],
/// keeping each paint's alpha. Every other colour (a green arrow, a red
/// badge) keeps its hue, so two-tone glyphs keep their accent; when [on] is
/// given that hue is also darkened to 3:1 against it.
///
/// ```dart
/// SvgPicture(
///   SvgAssetLoader(asset,
///       colorMapper: context.isLightTheme
///           ? InkColorMapper(context.colors.iconPrimary)
///           : null),
///   width: 20, height: 20,
/// )
/// ```
class InkColorMapper extends ColorMapper {
  const InkColorMapper(this.ink, {this.on});

  final Color ink;

  /// The surface the glyph sits on. When set, accent paints are darkened
  /// until they clear 3:1 against it.
  final Color? on;

  static bool _isWhite(Color c) {
    final rgb = c.toARGB32() & 0x00FFFFFF;
    return rgb == 0x00FFFFFF || rgb == 0x00FAFAFA;
  }

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (_isWhite(color)) return ink.withValues(alpha: color.a * ink.a);
    final surface = on;
    if (surface == null) return color;
    return legibleHueInkOn(color, surface, minContrast: 3);
  }

  @override
  bool operator ==(Object other) =>
      other is InkColorMapper && other.ink == ink && other.on == on;

  @override
  int get hashCode => Object.hash(ink, on);
}

/// A dark-first white SVG asset, re-inked on paper (accents darkened to 3:1
/// against [on], the theme background by default). Dark renders the asset
/// exactly as [SvgPicture.asset] would.
Widget inkedSvgAsset(
  BuildContext context,
  String asset, {
  double? width,
  double? height,
  Color? ink,
  Color? on,
  BoxFit fit = BoxFit.contain,
}) {
  return SvgPicture(
    SvgAssetLoader(
      asset,
      colorMapper: context.isLightTheme
          ? InkColorMapper(
              ink ?? context.colors.iconPrimary,
              on: on ?? context.colors.background,
            )
          : null,
    ),
    width: width,
    height: height,
    fit: fit,
  );
}
