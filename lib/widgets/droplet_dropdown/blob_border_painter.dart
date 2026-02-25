/// CustomPainter that draws animated "water droplet" morphing borders
/// Creates organic blob shapes that bulge and settle like liquid surface tension
library;

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// Paints an animated blob border that morphs between rounded rect and organic blob
///
/// The morph effect creates 8 control points around the rectangle that bulge
/// outward based on animation progress, creating a water droplet effect.
///
/// [morphProgress] drives the distortion wave (0.0-1.0)
/// [settleProgress] controls the snap-back to clean shape (0.0-1.0)
class BlobBorderPainter extends CustomPainter {
  final double morphProgress;
  final double settleProgress;
  final double baseRadius;
  final Color borderColor;
  final double borderWidth;
  final Color? fillColor;
  final double morphIntensity;

  /// Whether to apply glow effect to border
  final bool showGlow;
  final Color? glowColor;

  BlobBorderPainter({
    required this.morphProgress,
    required this.settleProgress,
    required this.baseRadius,
    required this.borderColor,
    this.borderWidth = 1.0,
    this.fillColor,
    this.morphIntensity = 0.06,
    this.showGlow = false, // Flat design default
    this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildBlobPath(size);

    // Draw glow layer first (behind fill)
    if (showGlow && morphProgress > 0 && settleProgress < 1.0) {
      final glowAmount =
          math.sin(morphProgress * math.pi) * (1.0 - settleProgress);
      if (glowAmount > 0.05) {
        final glowPaint =
            Paint()
              ..color = (glowColor ?? borderColor).withValues(
                alpha: glowAmount * 0.3,
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = borderWidth + 6.0
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
        canvas.drawPath(path, glowPaint);
      }
    }

    // Draw fill
    if (fillColor != null) {
      final fillPaint =
          Paint()
            ..color = fillColor!
            ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    }

    // Draw border stroke
    if (borderWidth > 0) {
      final borderPaint =
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, borderPaint);
    }
  }

  Path _buildBlobPath(Size size) {
    final w = size.width;
    final h = size.height;
    final r = baseRadius.clamp(0.0, math.min(w, h) / 2);

    // Calculate current distortion amount
    // Peaks at morphProgress=0.5, decays as settleProgress increases
    final distortionEnvelope = math.sin(morphProgress * math.pi);
    final distortion = distortionEnvelope * (1.0 - settleProgress);
    final maxBulge = math.min(w, h) * morphIntensity;
    final bulge = distortion * maxBulge;

    // Phase offset creates the "wobble" effect - different parts bulge at different times
    final phaseOffset = morphProgress * math.pi * 2.5;

    // When distortion is minimal, use simple rounded rect for performance
    if (bulge.abs() < 0.5) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
      );
    }

    final path = Path();

    // 8-point blob: 4 edges (midpoints) + 4 corners
    // Each point has base position + animated offset

    // Calculate bulge for each edge midpoint (sine wave with phase offset)
    final topBulge = bulge * math.sin(phaseOffset) * 0.7;
    final rightBulge = bulge * math.sin(phaseOffset + math.pi * 0.5) * 0.5;
    final bottomBulge = bulge * math.sin(phaseOffset + math.pi) * 0.8;
    final leftBulge = bulge * math.sin(phaseOffset + math.pi * 1.5) * 0.5;

    // Corner expansion (all corners expand/contract together)
    final cornerExpand = bulge * 0.4 * math.cos(phaseOffset * 0.8);

    // Build the blob path with smooth bezier curves

    // Start at top-left, after corner radius
    path.moveTo(r + cornerExpand, 0);

    // Top edge: straight to midpoint, then curve with bulge
    final topMidX = w / 2;
    path.quadraticBezierTo(
      topMidX,
      -topBulge, // Control point bulges up (negative Y)
      w - r - cornerExpand,
      0, // End at top-right before corner
    );

    // Top-right corner: smooth curve with expansion
    final trCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      w + trCornerOffset,
      -trCornerOffset, // Control point outside corner
      w,
      r + cornerExpand, // End at right edge after corner
    );

    // Right edge: curve with bulge
    final rightMidY = h / 2;
    path.quadraticBezierTo(
      w + rightBulge,
      rightMidY, // Control point bulges right
      w,
      h - r - cornerExpand, // End at bottom-right before corner
    );

    // Bottom-right corner
    final brCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      w + brCornerOffset,
      h + brCornerOffset,
      w - r - cornerExpand,
      h,
    );

    // Bottom edge: curve with bulge
    final bottomMidX = w / 2;
    path.quadraticBezierTo(
      bottomMidX,
      h + bottomBulge, // Control point bulges down
      r + cornerExpand,
      h,
    );

    // Bottom-left corner
    final blCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      -blCornerOffset,
      h + blCornerOffset,
      0,
      h - r - cornerExpand,
    );

    // Left edge: curve with bulge
    final leftMidY = h / 2;
    path.quadraticBezierTo(
      -leftBulge,
      leftMidY, // Control point bulges left
      0,
      r + cornerExpand,
    );

    // Top-left corner: close the path
    final tlCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      -tlCornerOffset,
      -tlCornerOffset,
      r + cornerExpand,
      0,
    );

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(BlobBorderPainter oldDelegate) {
    return morphProgress != oldDelegate.morphProgress ||
        settleProgress != oldDelegate.settleProgress ||
        borderColor != oldDelegate.borderColor ||
        fillColor != oldDelegate.fillColor ||
        baseRadius != oldDelegate.baseRadius ||
        morphIntensity != oldDelegate.morphIntensity;
  }
}

/// CustomClipper that uses the same blob path as BlobBorderPainter
/// Use this to clip content to the morphing blob shape
class BlobClipper extends CustomClipper<Path> {
  final double morphProgress;
  final double settleProgress;
  final double baseRadius;
  final double morphIntensity;

  BlobClipper({
    required this.morphProgress,
    required this.settleProgress,
    required this.baseRadius,
    this.morphIntensity = 0.06,
  });

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final r = baseRadius.clamp(0.0, math.min(w, h) / 2);

    // Calculate distortion
    final distortionEnvelope = math.sin(morphProgress * math.pi);
    final distortion = distortionEnvelope * (1.0 - settleProgress);
    final maxBulge = math.min(w, h) * morphIntensity;
    final bulge = distortion * maxBulge;

    // For clipping, use slightly inset path to avoid edge artifacts
    if (bulge.abs() < 0.5) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)),
      );
    }

    final phaseOffset = morphProgress * math.pi * 2.5;

    final topBulge = bulge * math.sin(phaseOffset) * 0.7;
    final rightBulge = bulge * math.sin(phaseOffset + math.pi * 0.5) * 0.5;
    final bottomBulge = bulge * math.sin(phaseOffset + math.pi) * 0.8;
    final leftBulge = bulge * math.sin(phaseOffset + math.pi * 1.5) * 0.5;
    final cornerExpand = bulge * 0.4 * math.cos(phaseOffset * 0.8);

    final path = Path();

    path.moveTo(r + cornerExpand, 0);

    path.quadraticBezierTo(w / 2, -topBulge, w - r - cornerExpand, 0);

    final trCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      w + trCornerOffset,
      -trCornerOffset,
      w,
      r + cornerExpand,
    );

    path.quadraticBezierTo(w + rightBulge, h / 2, w, h - r - cornerExpand);

    final brCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      w + brCornerOffset,
      h + brCornerOffset,
      w - r - cornerExpand,
      h,
    );

    path.quadraticBezierTo(w / 2, h + bottomBulge, r + cornerExpand, h);

    final blCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      -blCornerOffset,
      h + blCornerOffset,
      0,
      h - r - cornerExpand,
    );

    path.quadraticBezierTo(-leftBulge, h / 2, 0, r + cornerExpand);

    final tlCornerOffset = cornerExpand * 0.7;
    path.quadraticBezierTo(
      -tlCornerOffset,
      -tlCornerOffset,
      r + cornerExpand,
      0,
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(BlobClipper oldClipper) {
    return morphProgress != oldClipper.morphProgress ||
        settleProgress != oldClipper.settleProgress ||
        baseRadius != oldClipper.baseRadius;
  }
}
