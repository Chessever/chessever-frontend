import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BotvinnikIcon extends StatelessWidget {
  static const _asset = 'assets/svgs/botvinnik_icon.svg';

  const BotvinnikIcon({
    required this.size,
    this.showShadow = false,
    this.color,
    super.key,
  });

  final double size;
  final bool showShadow;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration:
          showShadow
              ? BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff42e8d4).withValues(alpha: 0.2),
                    blurRadius: size * 0.28,
                    offset: Offset(0, size * 0.1),
                  ),
                ],
              )
              : null,
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
      return BotvinnikIcon(size: widget.size, showShadow: true);
    }

    final canvasSize = widget.size * 1.36;
    return SizedBox.square(
      dimension: canvasSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final phase = _controller.value * math.pi * 2;
          return CustomPaint(
            painter: _BotvinnikOrbitPainter(
              phase: phase,
              color: const Color(0xff42e8d4),
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
        child: BotvinnikIcon(size: widget.size, showShadow: true),
      ),
    );
  }
}

class _BotvinnikOrbitPainter extends CustomPainter {
  const _BotvinnikOrbitPainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final orbitRadius = size.shortestSide * 0.43;
    final orbitRect = Rect.fromCircle(center: center, radius: orbitRadius);
    final ringPaint =
        Paint()
          ..color = color.withValues(alpha: 0.14)
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
    final glowPaint =
        Paint()
          ..color = color.withValues(alpha: opacity * 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(position, particleRadius * 2.3, glowPaint);
    canvas.drawCircle(
      position,
      particleRadius,
      Paint()..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _BotvinnikOrbitPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}
