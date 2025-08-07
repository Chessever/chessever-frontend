import 'dart:math';

import 'package:advanced_chess_board/models/chess_arrow.dart';
import 'package:flutter/material.dart';

import '../models/enums.dart';

class ArrowPainter extends CustomPainter {
  List<ChessArrow> arrows;
  PlayerColor boardOrientation;

  ArrowPainter(this.arrows, this.boardOrientation);

  @override
  void paint(final Canvas canvas, final Size size) {
    for (final arrow in arrows) {
      final (sourceRow, sourceCol) = getIndexFromSquare(arrow.startSquare);
      final (destRow, destCol) = getIndexFromSquare(arrow.endSquare);
      final blockSize = size.width / 8;

      // Calculate centers of the source and destination squares
      final sourceX = sourceCol * blockSize + (blockSize / 2);
      final sourceY = sourceRow * blockSize + (blockSize / 2);
      final destX = destCol * blockSize + (blockSize / 2);
      final destY = destRow * blockSize + (blockSize / 2);

      // Vector calculation between source and destination
      final dx = destX - sourceX;
      final dy = destY - sourceY;
      final distance = sqrt(dx * dx + dy * dy);

      // Define lengths for offsets and arrowhead sides
      final sourceThreshold = blockSize * 0.35;
      final destinationThreshold = blockSize * 0.272;
      final arrowheadSideLength = blockSize * 0.2;

      // Calculate the main line's adjusted endpoint (just before the base of the arrowhead triangle)
      final adjustedSourceX = sourceX + (dx / distance) * sourceThreshold;
      final adjustedSourceY = sourceY + (dy / distance) * sourceThreshold;
      final adjustedDestX =
          destX - (dx / distance) * (arrowheadSideLength * cos(pi / 6));
      final adjustedDestY =
          destY - (dy / distance) * (arrowheadSideLength * cos(pi / 6));
      final strokeDestX = destX - (dx / distance) * destinationThreshold;
      final strokeDestY = destY - (dy / distance) * destinationThreshold;

      // Draw the main arrow line
      final paint = Paint()
        ..color = arrow.color!
        ..strokeWidth = blockSize * 0.16;
      canvas.drawLine(Offset(adjustedSourceX, adjustedSourceY),
          Offset(strokeDestX, strokeDestY), paint);

      // Calculate points for the equilateral triangle arrowhead
      final angle = atan2(dy, dx);

      // Arrowhead points: tip at destination center, and two base points at the adjusted end of the line
      final tipX = destX;
      final tipY = destY;
      final baseX1 = adjustedDestX - arrowheadSideLength * cos(angle - pi / 3);
      final baseY1 = adjustedDestY - arrowheadSideLength * sin(angle - pi / 3);
      final baseX2 = adjustedDestX - arrowheadSideLength * cos(angle + pi / 3);
      final baseY2 = adjustedDestY - arrowheadSideLength * sin(angle + pi / 3);

      // Draw the equilateral triangle arrowhead
      final arrowheadPath = Path()
        ..moveTo(tipX, tipY)
        ..lineTo(baseX1, baseY1)
        ..lineTo(baseX2, baseY2)
        ..close();

      // Fill the arrowhead triangle
      final arrowheadPaint = Paint()..color = arrow.color!;
      canvas.drawPath(arrowheadPath, arrowheadPaint);
    }
  }

  (int, int) getIndexFromSquare(final String square) {
    var row = 8 - square[1].codeUnitAt(0) + 48;
    var col = square[0].codeUnitAt(0) - 97;
    if (boardOrientation == PlayerColor.black) {
      row = 7 - row;
      col = 7 - col;
    }
    return (row, col);
  }

  @override
  bool shouldRepaint(ArrowPainter oldDelegate) {
    if (arrows.length != oldDelegate.arrows.length) {
      return false;
    }
    for (var i = 0; i < arrows.length; i++) {
      if (arrows[i] != oldDelegate.arrows[i]) {
        return false;
      }
    }
    return true;
  }
}
