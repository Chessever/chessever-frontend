import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

/// A compact board-position mark for FEN actions.
///
/// The queen is deliberately anchored to f7 so the icon reads as a specific
/// position rather than a generic chessboard.
class FenPositionIcon extends StatelessWidget {
  const FenPositionIcon({required this.size, required this.color, super.key});

  static const queenSquare = Square.f7;

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Queen on f7 board position',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FenPositionPainter(color: color, queenSquare: queenSquare),
        ),
      ),
    );
  }
}

class _FenPositionPainter extends CustomPainter {
  const _FenPositionPainter({required this.color, required this.queenSquare});

  final Color color;
  final Square queenSquare;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;

    final strokeWidth = math.max(0.8, side * 0.06);
    final boardRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side - strokeWidth,
      height: side - strokeWidth,
    );
    final boardRadius = Radius.circular(side * 0.08);
    final boardShape = RRect.fromRectAndRadius(boardRect, boardRadius);
    final cell = boardRect.width / 8;

    canvas.save();
    canvas.clipRRect(boardShape);
    final squarePaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.2);
    for (var row = 0; row < 8; row++) {
      for (var file = 0; file < 8; file++) {
        if ((row + file).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(
              boardRect.left + file * cell,
              boardRect.top + row * cell,
              cell,
              cell,
            ),
            squarePaint,
          );
        }
      }
    }
    canvas.restore();

    canvas.drawRRect(
      boardShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final queenCenter = Offset(
      boardRect.left + (queenSquare.file.value + 0.5) * cell,
      boardRect.top + (7 - queenSquare.rank.value + 0.5) * cell,
    );
    _paintQueen(canvas, queenCenter, side);
  }

  void _paintQueen(Canvas canvas, Offset center, double boardSide) {
    final width = boardSide * 0.32;
    final height = boardSide * 0.31;
    final left = center.dx - width / 2;
    final top = center.dy - height / 2;
    final right = center.dx + width / 2;
    final bottom = center.dy + height / 2;
    final queenPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color;

    final crown =
        Path()
          ..moveTo(left + width * 0.04, top + height * 0.24)
          ..lineTo(left + width * 0.27, top + height * 0.49)
          ..lineTo(left + width * 0.5, top + height * 0.04)
          ..lineTo(left + width * 0.73, top + height * 0.49)
          ..lineTo(right - width * 0.04, top + height * 0.24)
          ..lineTo(right - width * 0.17, bottom - height * 0.28)
          ..lineTo(left + width * 0.17, bottom - height * 0.28)
          ..close();
    canvas.drawPath(crown, queenPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + width * 0.12,
          bottom - height * 0.28,
          width * 0.76,
          height * 0.13,
        ),
        Radius.circular(boardSide * 0.02),
      ),
      queenPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + width * 0.04,
          bottom - height * 0.12,
          width * 0.92,
          height * 0.12,
        ),
        Radius.circular(boardSide * 0.025),
      ),
      queenPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FenPositionPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.queenSquare != queenSquare;
  }
}
