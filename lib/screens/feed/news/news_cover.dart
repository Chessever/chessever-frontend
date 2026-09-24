import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// An article cover whose own pixels feather out at the top and bottom, so
/// it dissolves into whatever surface sits behind it with no seam.
///
/// The fade is a mask on the image (not a colour overlay), eased over many
/// stops so it never bands into a visible line.
class NewsCover extends StatelessWidget {
  const NewsCover({
    super.key,
    required this.imageUrl,
    this.fadeTop = 0,
    this.fadeBottom = 0.45,
    this.scale = 1,
    this.fallback,
  }) : assert(fadeTop >= 0 && fadeBottom >= 0 && fadeTop + fadeBottom <= 1);

  final String? imageUrl;

  /// Share of the height feathered to transparent at the top edge.
  final double fadeTop;

  /// Share of the height feathered to transparent at the bottom edge.
  final double fadeBottom;

  /// Scale of the picture inside the (fixed) mask, for the settle motion.
  final double scale;

  /// Shown when there is no cover or it fails to load; defaults to the
  /// ChessEver mark on a ground that follows the theme (black in dark, the
  /// page background in light).
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final width = constraints.maxWidth;
          final cacheWidth = width.isFinite && width > 0
              ? (width * dpr).round()
              : null;
          final missing =
              fallback ?? _BrandCover(fadeTop: fadeTop, fadeBottom: fadeBottom);
          Widget picture = url == null
              ? missing
              : NewsNetworkImage(
                  url: url,
                  pixelWidth: cacheWidth,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (context, _) =>
                      ColoredBox(color: context.colors.surface),
                  errorWidget: (context, _, _) => missing,
                );
          if (scale != 1) {
            picture = ClipRect(
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: picture,
              ),
            );
          }
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => newsFeatherGradient(
              top: fadeTop,
              bottom: fadeBottom,
            ).createShader(bounds),
            child: picture,
          );
        },
      ),
    );
  }
}

/// A news picture fetched at the size it is drawn, not as the original file.
///
/// News covers and inline images live in Supabase Storage, often as
/// multi-megabyte PNGs. For a public Storage object this asks the render
/// endpoint for a copy [pixelWidth] wide (WebP when the server can), the way
/// the web's next/image does; the Feed builds its neighbouring pages, so an
/// unresized cover would download even when the user never lands on it.
/// Any other host, or a render that fails, loads [url] untouched.
class NewsNetworkImage extends StatelessWidget {
  const NewsNetworkImage({
    super.key,
    required this.url,
    required this.pixelWidth,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String url;

  /// Width in physical pixels the picture is drawn at; also bounds the
  /// decoded bitmap. Null leaves both the request and the decode unsized.
  final int? pixelWidth;

  final BoxFit? fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// Asks for WebP but still accepts whatever the server has.
  static const Map<String, String> _acceptWebp = {
    'Accept': 'image/webp,image/*;q=0.8',
  };

  static final Curve _fadeInCurve = const CupertinoMotion.smooth().toCurve;
  static const Duration _fadeInDuration = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final target = pixelWidth;
    final resized = target == null
        ? null
        : newsResizedImageUri(url, pixelWidth: target);
    final original = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth: target,
      fadeInDuration: _fadeInDuration,
      fadeInCurve: _fadeInCurve,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
    if (resized == null) return original;
    return CachedNetworkImage(
      imageUrl: resized.toString(),
      httpHeaders: _acceptWebp,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth: target,
      fadeInDuration: _fadeInDuration,
      fadeInCurve: _fadeInCurve,
      placeholder: placeholder,
      errorWidget: (context, _, _) => original,
    );
  }
}

/// The Supabase Storage render URL for a public object at [pixelWidth]
/// (height follows the aspect ratio), or null when [url] is not a public
/// Storage object.
///
/// The width is rounded up to a 100px step (capped at the service's 2500) so
/// near-identical layouts share one cached download.
Uri? newsResizedImageUri(
  String url, {
  required int pixelWidth,
  int quality = 70,
}) {
  const objectPrefix = '/storage/v1/object/public/';
  const renderPrefix = '/storage/v1/render/image/public/';
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (!uri.path.startsWith(objectPrefix) ||
      uri.path.length == objectPrefix.length) {
    return null;
  }
  if (pixelWidth <= 0) return null;
  final width = ((pixelWidth / 100).ceil() * 100).clamp(100, 2500);
  return uri.replace(
    path: renderPrefix + uri.path.substring(objectPrefix.length),
    queryParameters: {
      ...uri.queryParameters,
      'width': '$width',
      'quality': '$quality',
    },
  );
}

/// Vertical alpha mask: transparent → opaque over [top], opaque in the
/// middle, opaque → transparent over [bottom]. Smootherstep-eased with a
/// dozen stops per edge so the fade never shows a band.
LinearGradient newsFeatherGradient({
  required double top,
  required double bottom,
}) {
  const steps = 12;
  double ease(double t) => t * t * t * (t * (t * 6 - 15) + 10);
  final colors = <Color>[];
  final stops = <double>[];
  if (top > 0) {
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      stops.add(top * t);
      colors.add(Colors.black.withValues(alpha: ease(t)));
    }
  } else {
    stops.add(0);
    colors.add(Colors.black);
  }
  if (bottom > 0) {
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      stops.add(1 - bottom + bottom * t);
      colors.add(Colors.black.withValues(alpha: 1 - ease(t)));
    }
  } else {
    stops.add(1);
    colors.add(Colors.black);
  }
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
    stops: stops,
  );
}

/// No cover (or it failed to load): the ChessEver mark, feathered like a
/// photo would be and centred in the band the feather leaves opaque, so the
/// mark stays whole.
///
/// Dark keeps the app icon on its own black, which melts into the dark page.
/// Light gets no slab at all: the ground is the page's own background, so
/// the feather has nothing to fade, and the mark is drawn in the brand's text
/// ink with the king cut out to that ground (5.9:1).
class _BrandCover extends StatelessWidget {
  const _BrandCover({required this.fadeTop, required this.fadeBottom});

  final double fadeTop;
  final double fadeBottom;

  /// Share of the icon's 800-unit canvas the mark itself spans (192..608).
  static const double _markShare = 416 / 800;

  /// Recolours the icon for paper: every pixel takes [ink], with alpha from
  /// the source's brightness. The cyan squares go solid; the black canvas and
  /// the black king go clear, so the ground shows through the king.
  static ColorFilter _inkFilter(Color ink) {
    const gain = 2.0; // brand cyan's luma (~0.58) lands just past opaque
    const floor = -0.1 * 255; // drops the canvas's compression noise
    return ColorFilter.matrix(<double>[
      0, 0, 0, 0, ink.r * 255, //
      0, 0, 0, 0, ink.g * 255, //
      0, 0, 0, 0, ink.b * 255, //
      0.2126 * gain, 0.7152 * gain, 0.0722 * gain, 0, floor,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    return ColoredBox(
      color: light ? colors.background : Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : width;
          final bandTop = height * fadeTop;
          final band = height * (1 - fadeTop - fadeBottom);
          final side = math.max(
            0.0,
            math.min(
              (math.min(width, height) * 0.62).clamp(64.0, 320.0),
              band * 0.8 / _markShare,
            ),
          );
          Widget mark = Image.asset(
            PngAsset.newAppLogo,
            width: side,
            height: side,
            fit: BoxFit.contain,
          );
          if (light) {
            mark = ColorFiltered(
              colorFilter: _inkFilter(colors.accentText),
              child: mark,
            );
          }
          return Stack(
            children: [
              Positioned(
                left: (width - side) / 2,
                top: bandTop + (band - side) / 2,
                width: side,
                height: side,
                child: mark,
              ),
            ],
          );
        },
      ),
    );
  }
}
