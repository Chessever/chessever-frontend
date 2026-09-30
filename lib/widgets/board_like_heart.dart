import 'package:flutter/material.dart';

/// Sets a mark on the top-left corner of every game-card board below it
/// (the boards drawn by `GameCardChessboard`), built for the board's size.
/// Most Liked uses it to set each game's like count on its board.
class BoardCornerBadge extends InheritedWidget {
  const BoardCornerBadge({
    super.key,
    required this.builder,
    required super.child,
  });

  final Widget Function(double boardSize) builder;

  static Widget Function(double boardSize)? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardCornerBadge>()?.builder;

  @override
  bool updateShouldNotify(BoardCornerBadge oldWidget) =>
      oldWidget.builder != builder;
}

/// The heart's width on a board [boardSize] across: about a square and a
/// quarter, never so small the figure blurs nor so big it hides the game.
double likeHeartSizeFor(double boardSize) =>
    (boardSize * 0.16).clamp(30.0, 52.0);

/// A heart holding a like count, to sit on a board: a solid dark heart (the
/// piece under it never shows through the figure) with the count in white,
/// fitted inside the heart's round upper body, the same on every board
/// theme.
class LikeCountHeart extends StatelessWidget {
  const LikeCountHeart({super.key, required this.likes, required this.size});

  final int likes;

  /// The heart's width; its height is 0.9 of it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = likes == 1 ? '1 like' : '$likes likes';
    final width = size;
    final height = size * 0.9;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: IgnorePointer(
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: const _HeartPainter(),
            child: Align(
              // The optical centre of the heart sits in its round upper half,
              // above the middle of its box.
              alignment: const Alignment(0, -0.22),
              // Inside the lobes with a margin to the outline even for the
              // widest count ("1.1K", "34K").
              child: SizedBox(
                width: width * 0.54,
                height: height * 0.4,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    likeHeartCount(likes),
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A like count short enough for a heart: "7", "842", "1.2K", "34K".
String likeHeartCount(int likes) {
  if (likes < 1000) return '$likes';
  if (likes < 10000) {
    final tenths = (likes / 100).floor();
    return tenths % 10 == 0 ? '${tenths ~/ 10}K' : '${tenths / 10}K';
  }
  return '${(likes / 1000).floor()}K';
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Two lobes meeting in a notch at the top, a point at the bottom.
    final path = Path()
      ..moveTo(w * 0.5, h * 0.98)
      ..cubicTo(w * 0.18, h * 0.74, 0, h * 0.52, 0, h * 0.3)
      ..cubicTo(0, h * 0.12, w * 0.14, 0, w * 0.29, 0)
      ..cubicTo(w * 0.39, 0, w * 0.46, h * 0.06, w * 0.5, h * 0.15)
      ..cubicTo(w * 0.54, h * 0.06, w * 0.61, 0, w * 0.71, 0)
      ..cubicTo(w * 0.86, 0, w, h * 0.12, w, h * 0.3)
      ..cubicTo(w, h * 0.52, w * 0.82, h * 0.74, w * 0.5, h * 0.98)
      ..close();
    // A solid ink body: a see-through one let the piece beneath (the a8
    // rook, a knight) read through the figure.
    canvas.drawPath(path, Paint()..color = const Color(0xFF0C0C0E).withValues(alpha: 0.88));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) => false;
}
