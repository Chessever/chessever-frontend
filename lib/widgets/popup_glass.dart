import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The material a centred popup is cut from: the floating buttons' frosted
/// glass ([GlassSurface]) at the size of a panel.
///
/// What is behind the panel (and only the panel) shows through, blurred,
/// under a plate of the popup's own surface tone. The plate is denser than a
/// button's, because a popup carries paragraphs: body text has to read at
/// 4.5:1 or better over the busiest page it can open on. A fine grain is
/// laid into the plate so the blurred wash never bands, the edge is the
/// plate's own lit rim (brighter at the top, where a soft sheen catches the
/// light), and the shadow is one tight contact shadow cast downwards, drawn
/// only outside the panel so it never darkens the glass from beneath.
@immutable
class PopupGlassStyle {
  const PopupGlassStyle({
    required this.plate,
    required this.rimTop,
    required this.rimBottom,
    required this.sheen,
    required this.shadow,
    required this.grain,
    required this.scrim,
  });

  /// How much of the plate covers the blurred backdrop.
  static const double _lightCover = 0.86;
  static const double _darkCover = 0.85;

  /// The plate over the blurred backdrop, already at its alpha.
  ///
  /// It is solved, not picked: over the page the popup opens on, dimmed by
  /// the scrim, the glass averages out to [tone], the popup's own surface.
  /// A plain tone at partial strength would sink toward the dimmed page (a
  /// grey cast on paper), and the controls inside that were drawn on that
  /// surface would stand out of it as tiles. The busy parts of the page
  /// (boards, pictures) still show through as frost.
  final Color plate;

  /// The rim, lit from above and fading toward the bottom.
  final Color rimTop;
  final Color rimBottom;

  /// The light along the top lip, fading out over [sheenDepth].
  final Color sheen;

  /// One light, from above: short, low, tinted.
  final BoxShadow shadow;

  /// How strongly the grain is laid into the plate (0 none).
  final double grain;

  /// The page dimming under a popup: the barrier's alpha at rest.
  final double scrim;

  /// How far the backdrop is blurred, in logical pixels of sigma. Wide
  /// enough that type and board squares behind melt into a wash, so nothing
  /// behind competes with the popup's own text.
  static const double blurSigma = 22;

  /// How far down the top sheen reaches.
  static const double sheenDepth = 36;

  /// The style for a popup whose surface is [tone] (the theme's surface
  /// when null): the colour its opaque panel used to be.
  static PopupGlassStyle of(BuildContext context, {Color? tone}) {
    final colors = context.colors;
    final surface = tone ?? colors.surface;
    if (context.isLightTheme) {
      const scrim = 0.30;
      return PopupGlassStyle(
        plate: _solvedPlate(
          tone: surface,
          page: _dimmed(colors.background, colors.scrim, scrim),
          cover: _lightCover,
        ),
        rimTop: Colors.white.withValues(alpha: 0.95),
        rimBottom: colors.textPrimary.withValues(alpha: 0.10),
        sheen: Colors.white.withValues(alpha: 0.45),
        shadow: BoxShadow(
          color: colors.textPrimary.withValues(alpha: 0.16),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
        grain: 0.025,
        scrim: scrim,
      );
    }
    const scrim = 0.62;
    return PopupGlassStyle(
      plate: _solvedPlate(
        tone: surface,
        page: _dimmed(colors.background, colors.scrim, scrim),
        cover: _darkCover,
      ),
      rimTop: Colors.white.withValues(alpha: 0.15),
      rimBottom: Colors.white.withValues(alpha: 0.04),
      sheen: Colors.white.withValues(alpha: 0.02),
      shadow: const BoxShadow(
        color: Color(0x66000000),
        blurRadius: 14,
        offset: Offset(0, 5),
      ),
      grain: 0.025,
      scrim: scrim,
    );
  }

  /// [page] under the barrier's tint at [strength], as the scrim draws it.
  static Color _dimmed(Color page, Color scrim, double strength) =>
      Color.alphaBlend(scrim.withValues(alpha: strength), page);

  /// The plate colour that, laid at [cover] over [page], gives [tone]:
  /// channel by channel `(tone - (1 - cover) * page) / cover`, held to what
  /// a colour can be.
  static Color _solvedPlate({
    required Color tone,
    required Color page,
    required double cover,
  }) {
    double solve(double t, double p) =>
        ((t - (1 - cover) * p) / cover).clamp(0.0, 1.0);
    return Color.from(
      alpha: cover,
      red: solve(tone.r, page.r),
      green: solve(tone.g, page.g),
      blue: solve(tone.b, page.b),
    );
  }
}

/// A centred popup's panel, in [PopupGlassStyle]'s frosted glass.
///
/// It takes the place of the popup's outer `Container`: [width], [height],
/// [constraints] and [padding] mean what they mean there, and [borderRadius]
/// is the panel's corner. The content is drawn on the glass unchanged, in a
/// repaint boundary of its own.
///
/// [tone] is the colour the popup's opaque panel was (the theme's surface
/// when null): the glass averages out to it, so what the popup draws on it
/// keeps the contrast it was designed with.
///
/// One backdrop filter, clipped to the panel's rounded rect, so only the
/// panel's area is blurred. It is never put in a [BackdropGroup]: a shared
/// backdrop is read once, before the scrim and the page above the group's
/// first filter are drawn, which is not what is behind a popup. Never put
/// the panel under an [Opacity] either: the filter would lose its backdrop
/// and the frost would drop out for the fade. Scale it.
class PopupGlass extends StatelessWidget {
  const PopupGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.width,
    this.height,
    this.constraints,
    this.padding,
    this.tone,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tone;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final style = PopupGlassStyle.of(context, tone: tone);
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    Widget content = RepaintBoundary(child: child);
    final inset = padding;
    if (inset != null) content = Padding(padding: inset, child: content);

    Widget panel = CustomPaint(
      // Drawn after the glass, so the blur never samples it.
      foregroundPainter: _ShadowPainter(
        borderRadius: borderRadius,
        shadow: style.shadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: PopupGlassStyle.blurSigma,
            sigmaY: PopupGlassStyle.blurSigma,
          ),
          child: CustomPaint(
            painter: _PlatePainter(
              style: style,
              borderRadius: borderRadius,
              devicePixelRatio: ratio,
            ),
            child: content,
          ),
        ),
      ),
    );

    var box = constraints;
    if (width != null || height != null) {
      box =
          box?.tighten(width: width, height: height) ??
          BoxConstraints.tightFor(width: width, height: height);
    }
    if (box != null) panel = ConstrainedBox(constraints: box, child: panel);
    return panel;
  }
}

/// The plate, its grain, the top sheen and the lit rim: everything the
/// glass is, behind the content.
class _PlatePainter extends CustomPainter {
  const _PlatePainter({
    required this.style,
    required this.borderRadius,
    required this.devicePixelRatio,
  });

  final PopupGlassStyle style;
  final BorderRadius borderRadius;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = style.plate);

    final grain = _Grain.tile;
    if (grain != null && style.grain > 0) {
      final scale = 1 / devicePixelRatio;
      canvas.drawRect(
        rect,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, style.grain)
          ..shader = ui.ImageShader(
            grain,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.diagonal3Values(scale, scale, 1).storage,
            filterQuality: FilterQuality.none,
          ),
      );
    }

    final sheenRect = Rect.fromLTWH(
      0,
      0,
      size.width,
      math.min(PopupGlassStyle.sheenDepth, size.height),
    );
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [style.sheen, style.sheen.withValues(alpha: 0)],
        ).createShader(sheenRect),
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [style.rimTop, style.rimBottom],
        // The lit lip is the top edge's; the sides settle to the quiet rim
        // within the first stretch of the panel.
        stops: [0, math.min(1, 96 / math.max(size.height, 1))],
      ).createShader(rect);
    canvas.drawRRect(borderRadius.toRRect(rect).deflate(0.5), rim);
  }

  @override
  bool shouldRepaint(_PlatePainter old) =>
      old.style.plate != style.plate ||
      old.style.rimTop != style.rimTop ||
      old.style.rimBottom != style.rimBottom ||
      old.style.sheen != style.sheen ||
      old.style.grain != style.grain ||
      old.borderRadius != borderRadius ||
      old.devicePixelRatio != devicePixelRatio;
}

/// The contact shadow, cast down from one light and drawn only outside the
/// panel: under translucent glass a shadow would show through as a darker
/// box inside it.
class _ShadowPainter extends CustomPainter {
  const _ShadowPainter({required this.borderRadius, required this.shadow});

  final BorderRadius borderRadius;
  final BoxShadow shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadow.color.a <= 0) return;
    final shape = borderRadius.toRRect(Offset.zero & size);
    final reach = shadow.blurRadius * 2 + shadow.offset.distance + 8;
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(shape.outerRect.inflate(reach))
        ..addRRect(shape),
    );
    canvas.drawRRect(
      shape.shift(shadow.offset).inflate(shadow.spreadRadius),
      shadow.toPaint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) =>
      old.shadow != shadow || old.borderRadius != borderRadius;
}

/// A tile of film grain, one texel per device pixel: equal parts lighter
/// and darker specks around a neutral middle, so laid over the plate it
/// dithers the blurred wash without shifting its tone.
abstract final class _Grain {
  static const int _side = 128;
  static ui.Image? _tile;
  static bool _failed = false;

  static ui.Image? get tile {
    if (_tile != null || _failed) return _tile;
    try {
      final random = math.Random(1709);
      // Four strengths each way: finer grain than one flat speck.
      final light = List.generate(4, (_) => <double>[]);
      final dark = List.generate(4, (_) => <double>[]);
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x++) {
          final v = random.nextDouble() * 2 - 1;
          final bucket = math.min(3, (v.abs() * 4).floor());
          (v >= 0 ? light : dark)[bucket]
            ..add(x + 0.5)
            ..add(y + 0.5);
        }
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var bucket = 0; bucket < 4; bucket++) {
        final alpha = (bucket + 1) / 4;
        for (final (points, base) in [
          (light[bucket], Colors.white),
          (dark[bucket], Colors.black),
        ]) {
          canvas.drawRawPoints(
            ui.PointMode.points,
            Float32List.fromList(points),
            Paint()
              ..color = base.withValues(alpha: alpha)
              ..strokeWidth = 1
              ..strokeCap = StrokeCap.square,
          );
        }
      }
      final picture = recorder.endRecording();
      _tile = picture.toImageSync(_side, _side);
      picture.dispose();
    } catch (_) {
      _failed = true;
    }
    return _tile;
  }
}
