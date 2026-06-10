import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sweep-gradient border shimmer used by the stadium-chip dropdown triggers.
/// Animates a soft accent-tinted highlight around the rounded-rect border.
class FluidShimmerPainter extends CustomPainter {
  FluidShimmerPainter({
    required this.progress,
    required this.shimmerColor,
    required this.borderRadius,
  });

  final double progress;
  final Color shimmerColor;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final sweepAngle = progress * 2 * math.pi;

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: sweepAngle,
      endAngle: sweepAngle + math.pi * 0.5,
      colors: [
        shimmerColor.withValues(alpha: 0),
        shimmerColor,
        shimmerColor.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint =
        Paint()
          ..shader = gradient.createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(FluidShimmerPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        shimmerColor != oldDelegate.shimmerColor ||
        borderRadius != oldDelegate.borderRadius;
  }
}
