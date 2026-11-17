import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'bracket_graph_layout.dart';

/// Draws the complete seeded route without turning planned arrows into winners.
class BracketConnectorPainter extends CustomPainter {
  const BracketConnectorPainter({
    required this.connections,
    required this.matchRects,
    required this.focusedMatchKey,
    required this.futureColor,
    required this.confirmedColor,
    required this.focusedColor,
    this.arrowheads = true,
  });

  final List<BracketConnection> connections;
  final Map<String, Rect> matchRects;
  final String? focusedMatchKey;
  final Color futureColor;
  final Color confirmedColor;
  final Color focusedColor;
  final bool arrowheads;

  @override
  void paint(Canvas canvas, Size size) {
    for (final focused in [false, true]) {
      for (final connection in connections) {
        final active =
            connection.isConfirmed &&
            focusedMatchKey != null &&
            (connection.sourceMatchKey == focusedMatchKey ||
                connection.destinationMatchKey == focusedMatchKey);
        if (active != focused) continue;
        final source = matchRects[connection.sourceMatchKey];
        final destination = matchRects[connection.destinationMatchKey];
        if (source == null || destination == null) continue;
        final paint = Paint()
          ..color = active
              ? focusedColor
              : connection.isConfirmed
              ? confirmedColor
              : futureColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = !arrowheads
              ? (active ? 2.1 : 1.2)
              : active
              ? 2
              : connection.isConfirmed
              ? 1.5
              : 1.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final start =
            source.centerRight + Offset(0, connection.feedsLosers ? 14 : 0);
        final end = destination.centerLeft;
        final middle = (start.dx + end.dx) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(middle, start.dy, middle, end.dy, end.dx, end.dy);
        if (connection.feedsLosers) {
          for (final metric in path.computeMetrics()) {
            for (var offset = 0.0; offset < metric.length; offset += 9) {
              canvas.drawPath(
                metric.extractPath(offset, math.min(offset + 5, metric.length)),
                paint,
              );
            }
          }
        } else {
          canvas.drawPath(path, paint);
        }
        if (arrowheads) {
          canvas.drawPath(
            Path()
              ..moveTo(end.dx - 4, end.dy - 3)
              ..lineTo(end.dx, end.dy)
              ..lineTo(end.dx - 4, end.dy + 3),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant BracketConnectorPainter old) =>
      old.arrowheads != arrowheads ||
      old.connections != connections ||
      old.matchRects != matchRects ||
      old.focusedMatchKey != focusedMatchKey ||
      old.futureColor != futureColor ||
      old.confirmedColor != confirmedColor ||
      old.focusedColor != focusedColor;
}
