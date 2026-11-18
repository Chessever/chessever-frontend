import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The frosted material floating controls are cut from: what is under them
/// shows through, blurred, behind a thin plate of the page's own tone.
///
/// It is quiet on purpose. The plate is the page colour at partial strength
/// (smoky in dark, frosted white on paper), the edge is the plate's own lit
/// rim (a hair brighter at the top, where light would catch it) rather than
/// a drawn outline, and the only shadow is a tight one-light contact shadow.
/// No glow, no tinted bloom: the control should feel like part of the page,
/// not a sticker on it.
@immutable
class GlassStyle {
  const GlassStyle({
    required this.plate,
    required this.rimTop,
    required this.rimBottom,
    required this.shadow,
    required this.ink,
  });

  /// The tint over the blurred backdrop.
  final Color plate;

  /// The rim, lit from above and fading toward the bottom.
  final Color rimTop;
  final Color rimBottom;

  /// One light: tight, short, low.
  final List<BoxShadow> shadow;

  /// Glyphs and text on the glass.
  final Color ink;

  /// How far the backdrop is blurred, in logical pixels of sigma.
  static const double blurSigma = 14;

  static GlassStyle of(BuildContext context) {
    final colors = context.colors;
    if (context.isLightTheme) {
      return GlassStyle(
        plate: Colors.white.withValues(alpha: 0.62),
        rimTop: Colors.white.withValues(alpha: 0.9),
        rimBottom: colors.textPrimary.withValues(alpha: 0.08),
        // Short and soft enough that no crescent of a second disc shows
        // under the glass on paper.
        shadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.07),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        ink: colors.textPrimary.withValues(alpha: 0.86),
      );
    }
    return GlassStyle(
      plate: Color.lerp(
        colors.background,
        colors.surface,
        0.5,
      )!.withValues(alpha: 0.58),
      rimTop: Colors.white.withValues(alpha: 0.16),
      rimBottom: Colors.white.withValues(alpha: 0.04),
      shadow: const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
      ink: colors.textPrimary.withValues(alpha: 0.88),
    );
  }
}

/// A [GlassStyle] surface of [shape]: the blurred backdrop, the plate, the
/// lit rim. [tint] lays a little colour over the plate (a control that is
/// on); [lift] brightens it (a press).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.tint,
    this.lift = 0,
  });

  final Widget child;

  /// Null for a circle.
  final BorderRadius? borderRadius;
  final Color? tint;

  /// 0 at rest to 1 fully pressed.
  final double lift;

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.of(context);
    final light = context.isLightTheme;
    var plate = style.plate;
    final tint = this.tint;
    if (tint != null) plate = Color.alphaBlend(tint, plate);
    if (lift > 0) {
      plate = Color.lerp(
        plate,
        light ? Colors.white : Colors.white.withValues(alpha: 0.9),
        0.10 * lift.clamp(0.0, 1.0),
      )!;
    }
    final radius = borderRadius;
    final clip = radius == null
        ? ClipOval(child: _frost(plate, child))
        : ClipRRect(borderRadius: radius, child: _frost(plate, child));
    return DecoratedBox(
      // The contact shadow sits outside the clip, so it is drawn from the
      // shape, not from a box behind it.
      decoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        boxShadow: style.shadow,
      ),
      child: CustomPaint(
        foregroundPainter: _RimPainter(
          top: style.rimTop,
          bottom: style.rimBottom,
          borderRadius: radius,
        ),
        child: clip,
      ),
    );
  }

  Widget _frost(Color plate, Widget child) => BackdropFilter(
    filter: ui.ImageFilter.blur(
      sigmaX: GlassStyle.blurSigma,
      sigmaY: GlassStyle.blurSigma,
    ),
    child: ColoredBox(color: plate, child: child),
  );
}

class _RimPainter extends CustomPainter {
  const _RimPainter({
    required this.top,
    required this.bottom,
    required this.borderRadius,
  });

  final Color top;
  final Color bottom;
  final BorderRadius? borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(rect);
    final radius = borderRadius;
    if (radius == null) {
      canvas.drawCircle(rect.center, size.shortestSide / 2 - 0.5, paint);
    } else {
      canvas.drawRRect(radius.toRRect(rect).deflate(0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.borderRadius != borderRadius;
}
