import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BotvinnikIcon extends StatelessWidget {
  static const _asset = 'assets/svgs/botvinnik_icon.svg';

  /// Light-theme tint. The artwork is teal with black glasses and mouth,
  /// multiplied through [BlendMode.modulate]: brand cyan leaves the body at
  /// ~2.6:1 on mint paper, and the deeper accent-text teal drowns the black
  /// features (2.4:1). This tint lands the body near #04808F, ~3.9:1 on the
  /// background and ~4.4:1 on the surface, with the features still ~4.5:1
  /// against the body.
  static const paperTint = Color(0xFF0D92AF);

  /// The tint [BotvinnikIcon] applies when no colour is passed: brand
  /// primary in dark (unchanged), [paperTint] in light.
  static Color defaultTint(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.light
        ? paperTint
        : theme.colorScheme.primary;
  }

  const BotvinnikIcon({
    required this.size,
    this.showShadow = false,
    this.color,
    super.key,
  });

  final double size;

  /// Kept so existing call sites compile. The mark is drawn bare in both
  /// themes: the old teal bloom was the icon's own rounded box blurred
  /// behind it, a halo rather than light.
  final bool showShadow;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? defaultTint(context);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: SvgPicture.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(effectiveColor, BlendMode.modulate),
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// The Botvinnik logo in its own colours, trimmed to its artwork.
///
/// [BotvinnikIcon] draws `botvinnik_icon.svg`, a PNG wrapped in a 1024 canvas
/// whose crown-and-bubble fills barely half of it, tinted through
/// `BlendMode.modulate`. At launcher sizes that left a dim speck. This asset
/// is the same artwork cropped to its opaque bounds with an even 2% margin,
/// edge pixels un-matted from the black they were anti-aliased against, and
/// drawn untinted so the logo's teal and black read exactly as designed.
class BotvinnikMark extends StatelessWidget {
  const BotvinnikMark({required this.size, this.semanticLabel, super.key});

  static const asset = 'assets/pngs/botvinnik_mark.png';

  /// Pixel width of [asset]; decoding never goes past it.
  static const _assetExtent = 384;

  /// Share of the square the artwork spans top to bottom (it is portrait, so
  /// its width is ~68% of the square and its height ~96%).
  static const artworkHeightFactor = 0.96;

  /// The logo's own teal, sampled from the artwork.
  static const teal = Color(0xFF4FE0D0);

  /// Side of the square slot the mark is drawn in.
  final double size;

  /// Announced label, when the mark stands alone. Null keeps it decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    // Decode at the drawn size: the codec downsamples once, cleanly, instead
    // of the GPU minifying a 384px texture on every frame.
    final decodeWidth = (size * dpr).ceil().clamp(1, _assetExtent);
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: decodeWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

class BotvinnikAnimatedIcon extends StatefulWidget {
  const BotvinnikAnimatedIcon({required this.size, super.key});

  final double size;

  @override
  State<BotvinnikAnimatedIcon> createState() => _BotvinnikAnimatedIconState();
}

class _BotvinnikAnimatedIconState extends State<BotvinnikAnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion && _controller.isAnimating) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return BotvinnikIcon(size: widget.size);
    }

    final canvasSize = widget.size * 1.36;
    final light = Theme.of(context).brightness == Brightness.light;
    return SizedBox.square(
      dimension: canvasSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final phase = _controller.value * math.pi * 2;
          return CustomPaint(
            painter: _BotvinnikOrbitPainter(
              phase: phase,
              color:
                  light
                      ? _BotvinnikOrbitPainter.paperColor
                      : _BotvinnikOrbitPainter.stageColor,
              light: light,
            ),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, math.sin(phase) * -2.5),
                child: Transform.scale(
                  scale: 1 + math.sin(phase) * 0.018,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: BotvinnikIcon(size: widget.size),
      ),
    );
  }
}

class _BotvinnikOrbitPainter extends CustomPainter {
  const _BotvinnikOrbitPainter({
    required this.phase,
    required this.color,
    this.light = false,
  });

  /// Orbit teal on the dark stage.
  static const stageColor = Color(0xff42e8d4);

  /// Orbit teal on paper: the icon's own body tone, solid, so the ring and
  /// particles read as marks rather than a pale haze.
  static const paperColor = Color(0xFF04808F);

  final double phase;
  final Color color;

  /// Paper firms up the ring. Particles are solid dots in both themes, with
  /// no blurred halo under them.
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final orbitRadius = size.shortestSide * 0.43;
    final orbitRect = Rect.fromCircle(center: center, radius: orbitRadius);
    final ringPaint =
        Paint()
          ..color = color.withValues(alpha: light ? 0.22 : 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1;
    canvas.drawArc(orbitRect, phase + 0.3, math.pi * 0.72, false, ringPaint);
    canvas.drawArc(
      orbitRect,
      phase + math.pi + 0.3,
      math.pi * 0.54,
      false,
      ringPaint,
    );

    _drawParticle(canvas, center, orbitRadius, phase, 2.7, 0.92);
    _drawParticle(canvas, center, orbitRadius, phase + math.pi, 1.9, 0.62);
  }

  void _drawParticle(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    double particleRadius,
    double opacity,
  ) {
    final position = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawCircle(
      position,
      particleRadius,
      Paint()..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _BotvinnikOrbitPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.light != light;
  }
}
