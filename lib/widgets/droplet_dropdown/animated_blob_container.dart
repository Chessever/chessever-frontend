/// Animated container with water droplet morphing border effect
/// Uses the motor package for premium spring physics animations
library;

import 'dart:math' as math;
import 'package:chessever2/widgets/droplet_dropdown/blob_border_painter.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// A container that animates with water droplet-like border morphing
/// Uses motor package for buttery smooth spring physics
///
/// When [isExpanded] changes, the container:
/// 1. Pops into view with bouncy spring overshoot
/// 2. Border morphs outward like surface tension
/// 3. Settles back to clean rounded rect with elastic bounce
class AnimatedBlobContainer extends StatelessWidget {
  final Widget child;
  final bool isExpanded;
  final double borderRadius;
  final Color borderColor;
  final Color backgroundColor;
  final double borderWidth;
  final double morphIntensity;
  final bool enableHaptics;

  const AnimatedBlobContainer({
    super.key,
    required this.child,
    required this.isExpanded,
    this.borderRadius = 16.0,
    this.borderColor = const Color(0x400FB4E5),
    this.backgroundColor = const Color(0xF51A1A1C),
    this.borderWidth = 1.0,
    this.morphIntensity = 0.06,
    this.enableHaptics = true,
  });

  @override
  Widget build(BuildContext context) {
    // Padding to accommodate blob bulge during morph
    final morphPadding = morphIntensity * 100 + 8;

    return RepaintBoundary(
      // Scale animation with bouncy spring
      child: SingleMotionBuilder(
        motion: CupertinoMotion.bouncy(),
        value: isExpanded ? 1.0 : 0.0,
        builder: (context, scaleProgress, child) {
          // Scale: starts small, overshoots slightly, settles at 1.0
          final scale = 0.85 + (scaleProgress * 0.15);
          final opacity = scaleProgress.clamp(0.0, 1.0);

          // Morph progress for border distortion effect
          // Peak distortion at 0.5, then settle back
          final morphProgress = scaleProgress;
          final settleProgress = scaleProgress > 0.5
              ? ((scaleProgress - 0.5) * 2.0).clamp(0.0, 1.0)
              : 0.0;

          return Opacity(
            opacity: opacity,
            child: Padding(
              padding: EdgeInsets.all(morphPadding),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: CustomPaint(
                  painter: BlobBorderPainter(
                    morphProgress: morphProgress,
                    settleProgress: settleProgress,
                    baseRadius: borderRadius,
                    borderColor: borderColor,
                    borderWidth: borderWidth,
                    fillColor: backgroundColor,
                    morphIntensity: morphIntensity,
                    showGlow: false, // Flat design - no glow
                  ),
                  child: ClipPath(
                    clipper: BlobClipper(
                      morphProgress: morphProgress,
                      settleProgress: settleProgress,
                      baseRadius: borderRadius,
                      morphIntensity: morphIntensity,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }
}

/// Water droplet selector that floats and lands on items
/// Uses motor springs for fluid, organic motion
class WaterDropletSelector extends StatelessWidget {
  final double targetTop;
  final double targetHeight;
  final double width;
  final Color color;
  final double borderRadius;

  const WaterDropletSelector({
    super.key,
    required this.targetTop,
    required this.targetHeight,
    required this.width,
    this.color = const Color(0x300FB4E5),
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return MotionBuilder(
      motion: CupertinoMotion.snappy(),
      value: Offset(0, targetTop),
      converter: OffsetMotionConverter(),
      builder: (context, offset, child) {
        // Calculate "squish" effect based on velocity
        // When moving fast, the droplet stretches in direction of travel
        return SingleMotionBuilder(
          motion: CupertinoMotion.bouncy(),
          value: targetHeight,
          builder: (context, height, _) {
            return Positioned(
              left: 0,
              right: 0,
              top: offset.dy,
              child: _WaterDropletShape(
                height: height,
                width: width,
                color: color,
                borderRadius: borderRadius,
              ),
            );
          },
        );
      },
    );
  }
}

/// The actual droplet shape with wobbly border
class _WaterDropletShape extends StatefulWidget {
  final double height;
  final double width;
  final Color color;
  final double borderRadius;

  const _WaterDropletShape({
    required this.height,
    required this.width,
    required this.color,
    required this.borderRadius,
  });

  @override
  State<_WaterDropletShape> createState() => _WaterDropletShapeState();
}

class _WaterDropletShapeState extends State<_WaterDropletShape>
    with SingleTickerProviderStateMixin {
  late AnimationController _wobbleController;

  @override
  void initState() {
    super.initState();
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wobbleController,
      builder: (context, child) {
        return Container(
          height: widget.height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: CustomPaint(
            painter: _DropletPainter(
              wobblePhase: _wobbleController.value * 2 * math.pi,
              color: widget.color,
              borderRadius: widget.borderRadius,
            ),
            size: Size(widget.width - 12, widget.height),
          ),
        );
      },
    );
  }
}

/// Paints a gently wobbling droplet shape
class _DropletPainter extends CustomPainter {
  final double wobblePhase;
  final Color color;
  final double borderRadius;

  _DropletPainter({
    required this.wobblePhase,
    required this.color,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = borderRadius.clamp(0.0, math.min(w, h) / 2);

    // Subtle wobble amplitude
    final wobbleAmp = 1.5;

    // Create wobbly rounded rect path
    final path = Path();

    // Calculate wobble offsets for each edge
    final topWobble = math.sin(wobblePhase) * wobbleAmp;
    final rightWobble = math.sin(wobblePhase + math.pi * 0.5) * wobbleAmp;
    final bottomWobble = math.sin(wobblePhase + math.pi) * wobbleAmp;
    final leftWobble = math.sin(wobblePhase + math.pi * 1.5) * wobbleAmp;

    path.moveTo(r, topWobble);

    // Top edge with wobble
    path.quadraticBezierTo(w / 2, topWobble - 1, w - r, topWobble);

    // Top-right corner
    path.quadraticBezierTo(w + rightWobble, topWobble, w + rightWobble, r);

    // Right edge
    path.quadraticBezierTo(w + rightWobble, h / 2, w + rightWobble, h - r);

    // Bottom-right corner
    path.quadraticBezierTo(w + rightWobble, h + bottomWobble, w - r, h + bottomWobble);

    // Bottom edge
    path.quadraticBezierTo(w / 2, h + bottomWobble + 1, r, h + bottomWobble);

    // Bottom-left corner
    path.quadraticBezierTo(leftWobble, h + bottomWobble, leftWobble, h - r);

    // Left edge
    path.quadraticBezierTo(leftWobble, h / 2, leftWobble, r);

    // Top-left corner
    path.quadraticBezierTo(leftWobble, topWobble, r, topWobble);

    path.close();

    // Flat solid fill - no gradient
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Clean border stroke - no glow
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_DropletPainter oldDelegate) {
    return wobblePhase != oldDelegate.wobblePhase;
  }
}

/// Simplified spring scale animation using motor
class MotorScaleTransition extends StatelessWidget {
  final Widget child;
  final bool isVisible;
  final Alignment alignment;

  const MotorScaleTransition({
    super.key,
    required this.child,
    required this.isVisible,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: CupertinoMotion.bouncy(),
      value: isVisible ? 1.0 : 0.0,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + (value * 0.2),
          alignment: alignment,
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
