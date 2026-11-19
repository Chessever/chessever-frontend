import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    this.liftColor = const Color(0xFFFFFFFF),
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

  /// What a press brightens the plate toward.
  final Color liftColor;

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
      liftColor: Colors.white.withValues(alpha: 0.9),
    );
  }
}

/// One [GlassStyle] resolved for a moment: the plate with its tint and press
/// folded in, everything scaled by a fade, and an optional solid fill laid
/// over the plate. [GlassSurface] draws it as widgets, [GlassPainter] at
/// paint time; both go through [GlassLook.resolve], so the two can never
/// disagree by a shade.
@immutable
class GlassLook {
  const GlassLook({
    required this.plate,
    required this.rimTop,
    required this.rimBottom,
    required this.shadow,
    required this.sigma,
    this.fill,
  });

  /// [fade] is how much of the glass is there (1 the whole material, 0
  /// nothing): it scales the plate's, rim's and shadow's alphas and the blur.
  /// [fill], at [fillAmount] of its own alpha, is laid over the plate inside
  /// the shape: the glass turning into a solid surface.
  factory GlassLook.resolve(
    GlassStyle style, {
    Color? tint,
    double lift = 0,
    double fade = 1,
    Color? fill,
    double fillAmount = 0,
  }) {
    var plate = style.plate;
    if (tint != null) plate = Color.alphaBlend(tint, plate);
    if (lift > 0) {
      plate = Color.lerp(plate, style.liftColor, 0.10 * lift.clamp(0.0, 1.0))!;
    }
    final f = fade.clamp(0.0, 1.0);
    Color scaled(Color c) => f >= 1 ? c : c.withValues(alpha: c.a * f);
    final amount = fillAmount.clamp(0.0, 1.0);
    return GlassLook(
      plate: scaled(plate),
      rimTop: scaled(style.rimTop),
      rimBottom: scaled(style.rimBottom),
      shadow: f >= 1
          ? style.shadow
          : [
              for (final s in style.shadow)
                BoxShadow(
                  color: scaled(s.color),
                  offset: s.offset,
                  blurRadius: s.blurRadius,
                  spreadRadius: s.spreadRadius,
                  blurStyle: s.blurStyle,
                ),
            ],
      sigma: GlassStyle.blurSigma * f,
      fill: fill?.withValues(alpha: fill.a * amount),
    );
  }

  final Color plate;
  final Color rimTop;
  final Color rimBottom;
  final List<BoxShadow> shadow;

  /// The backdrop blur; 0 draws no backdrop filter at all.
  final double sigma;

  /// The solid laid over the plate, already at its strength; null for none.
  final Color? fill;

  bool get blurs => sigma > 0.01;
}

/// A [GlassStyle] surface of [shape]: the blurred backdrop, the plate, the
/// lit rim. [tint] lays a little colour over the plate (a control that is
/// on); [lift] brightens it (a press).
///
/// [fade] takes the material away without an [Opacity] around the backdrop
/// filter: it scales the plate, rim and shadow alphas and the blur sigma
/// (and drops the filter at 0). [fill] is a solid laid over the plate at
/// [fillAmount], so a fade with a rising fill turns the glass into that
/// surface.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.tint,
    this.lift = 0,
    this.fade = 1,
    this.fill,
    this.fillAmount = 0,
  });

  final Widget child;

  /// Null for a circle.
  final BorderRadius? borderRadius;
  final Color? tint;

  /// 0 at rest to 1 fully pressed.
  final double lift;

  /// 1 the whole glass, 0 none of it (the child stays). Multiplied by a
  /// [GlassFade] above it, which fades the child too.
  final double fade;

  /// A solid laid over the plate, at [fillAmount] of its alpha.
  final Color? fill;
  final double fillAmount;

  @override
  Widget build(BuildContext context) {
    final inherited = GlassFade.maybeOf(context);
    if (inherited == null) return _surface(context, fade, child);
    // The content fades in its own layer, inside the backdrop filter: the
    // filter itself is never under an opacity.
    final content = FadeTransition(opacity: inherited, child: child);
    return AnimatedBuilder(
      animation: inherited,
      builder: (context, _) =>
          _surface(context, fade * inherited.value.clamp(0.0, 1.0), content),
    );
  }

  Widget _surface(BuildContext context, double fade, Widget child) {
    final look = GlassLook.resolve(
      GlassStyle.of(context),
      tint: tint,
      lift: lift,
      fade: fade,
      fill: fill,
      fillAmount: fillAmount,
    );
    final radius = borderRadius;
    // The fill's box is there whenever a fill is asked for, at any amount,
    // so a fill coming in never rebuilds the child.
    final filled = fill == null
        ? child
        : ColoredBox(color: look.fill!, child: child);
    final frost = BackdropFilter(
      enabled: look.blurs,
      filter: ui.ImageFilter.blur(sigmaX: look.sigma, sigmaY: look.sigma),
      child: ColoredBox(color: look.plate, child: filled),
    );
    final clip = radius == null
        ? ClipOval(child: frost)
        : ClipRRect(borderRadius: radius, child: frost);
    return DecoratedBox(
      // The contact shadow sits outside the clip, so it is drawn from the
      // shape, not from a box behind it.
      decoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        boxShadow: look.shadow,
      ),
      child: CustomPaint(
        foregroundPainter: _RimPainter(
          top: look.rimTop,
          bottom: look.rimBottom,
          borderRadius: radius,
        ),
        child: clip,
      ),
    );
  }
}

/// A fade every [GlassSurface] under it takes on: a floating control
/// stepping back as another takes the stage.
///
/// An [Opacity] (or a `FadeTransition`) around glass puts its backdrop
/// filter inside an offscreen layer with nothing behind it to blur, so the
/// frost drops out the frame the fade starts. Under a [GlassFade] each
/// [GlassSurface] instead scales its own material (plate, rim, shadow, blur)
/// by [opacity] and fades only its content. Anything a control draws beside
/// its glass (a count on its shoulder) fades with [GlassFade.content].
class GlassFade extends InheritedWidget {
  const GlassFade({super.key, required this.opacity, required super.child});

  /// 1 the glass in full, 0 none of it.
  final Animation<double> opacity;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassFade>()?.opacity;

  /// [child], drawn outside any glass, fading with the [GlassFade] above
  /// [context] (as it is with none).
  static Widget content(BuildContext context, Widget child) {
    final opacity = maybeOf(context);
    return opacity == null
        ? child
        : FadeTransition(opacity: opacity, child: child);
  }

  @override
  bool updateShouldNotify(GlassFade oldWidget) => oldWidget.opacity != opacity;
}

/// [GlassSurface]'s material drawn at paint time, for a shape only known
/// then (a surface in flight between two laid-out boxes).
///
/// Layers are pushed (a clip, the backdrop filter), so the render object
/// calling it must report `alwaysNeedsCompositing` while it does.
abstract final class GlassPainter {
  /// Paints [look] in [shape] (paint coordinates).
  ///
  /// [excluding] leaves a rectangle out (another painter draws the glass
  /// there); [within] draws only inside one. Both cut on hard pixel edges, so
  /// two painters given the same rectangle, one as [excluding] and one as
  /// [within], meet with no seam. The contact shadow is drawn only when
  /// [shadow] is true, and never inside [excluding].
  static void paint(
    PaintingContext context, {
    required RRect shape,
    required GlassLook look,
    required Rect bounds,
    Rect? excluding,
    Rect? within,
    bool shadow = true,
  }) {
    final outside = excluding == null ? null : _minus(bounds, excluding);
    if (shadow && look.shadow.any((s) => s.color.a > 0)) {
      final canvas = context.canvas;
      canvas.save();
      if (outside != null) canvas.clipPath(outside, doAntiAlias: false);
      if (within != null) canvas.clipRect(within, doAntiAlias: false);
      for (final s in look.shadow) {
        if (s.color.a <= 0) continue;
        canvas.drawRRect(
          shape.shift(s.offset).inflate(s.spreadRadius),
          s.toPaint(),
        );
      }
      canvas.restore();
    }

    void material(PaintingContext context, Offset _) {
      final area = shape.outerRect;
      void plate(PaintingContext context, Offset _) {
        final canvas = context.canvas;
        if (look.plate.a > 0) {
          canvas.drawRect(area, Paint()..color = look.plate);
        }
        final fill = look.fill;
        if (fill != null && fill.a > 0) {
          canvas.drawRect(area, Paint()..color = fill);
        }
      }

      if (look.blurs) {
        context.pushLayer(
          BackdropFilterLayer(
            filter: ui.ImageFilter.blur(sigmaX: look.sigma, sigmaY: look.sigma),
          ),
          plate,
          Offset.zero,
        );
      } else {
        plate(context, Offset.zero);
      }
      paintGlassRim(context.canvas, shape, look.rimTop, look.rimBottom);
    }

    void shaped(PaintingContext context, Offset _) => context.pushClipRRect(
      true,
      Offset.zero,
      shape.outerRect,
      shape,
      material,
    );

    if (outside != null) {
      context.pushClipPath(
        true,
        Offset.zero,
        bounds.expandToInclude(excluding!),
        outside,
        shaped,
        clipBehavior: Clip.hardEdge,
      );
    } else if (within != null) {
      context.pushClipRect(true, Offset.zero, within, shaped);
    } else {
      shaped(context, Offset.zero);
    }
  }

  /// [bounds] with [hole] cut out.
  static Path _minus(Rect bounds, Rect hole) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(bounds.expandToInclude(hole))
    ..addRect(hole);
}

/// The lit rim of a glass [shape]: a hairline lit from above, fading toward
/// the bottom.
void paintGlassRim(Canvas canvas, RRect shape, Color top, Color bottom) {
  if (top.a <= 0 && bottom.a <= 0) return;
  final rect = shape.outerRect;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bottom],
    ).createShader(rect);
  canvas.drawRRect(shape.deflate(0.5), paint);
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
    final radius = borderRadius;
    if (radius == null) {
      if (top.a <= 0 && bottom.a <= 0) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect);
      canvas.drawCircle(rect.center, size.shortestSide / 2 - 0.5, paint);
    } else {
      paintGlassRim(canvas, radius.toRRect(rect), top, bottom);
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.borderRadius != borderRadius;
}
