import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_session.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:motor/motor.dart';

/// How Feed draws a [MoveClass]: the same badge assets and palette the board
/// screen, the notation list and the Game Review recap use
/// (`classification_style.dart`), so a Feed "Blunder" is the board's
/// "Blunder" to the pixel.

/// The badge asset family for [moveClass]; null for `!?`, which has no badge
/// and is drawn as its glyph (the board's Unicode-badge path).
LichessMoveAnnotationType? feedAnnotationType(MoveClass moveClass) =>
    switch (moveClass) {
      MoveClass.brilliant => LichessMoveAnnotationType.brilliant,
      MoveClass.great => LichessMoveAnnotationType.goodMove,
      MoveClass.best => LichessMoveAnnotationType.bestMove,
      MoveClass.inaccuracy => LichessMoveAnnotationType.inaccuracy,
      MoveClass.mistake => LichessMoveAnnotationType.mistake,
      MoveClass.blunder => LichessMoveAnnotationType.blunder,
      MoveClass.missedWin => LichessMoveAnnotationType.missedWin,
      MoveClass.book => LichessMoveAnnotationType.bookMove,
      MoveClass.interesting => null,
    };

/// Text tint for [moveClass] (the badge SVG's top gradient stop).
Color feedClassColor(MoveClass moveClass) {
  final type = feedAnnotationType(moveClass);
  if (type != null) return moveAnnotationColor(type);
  return getNagDisplay(5)?.color ?? const Color(0xFF5B9BD5);
}

/// [feedClassColor] lifted until it reads as text on the Feed's dark
/// surface. The badge palette tracks each SVG's gradient top, and a couple of
/// those (the navy `!`) sink into a near-black page as glyphs; the hue stays,
/// only the lightness comes up.
Color feedClassTextColor(MoveClass moveClass) {
  final base = HSLColor.fromColor(feedClassColor(moveClass));
  if (base.lightness >= 0.45) return base.toColor();
  return base.withLightness(0.6).toColor();
}

/// [feedClassColor] as text on the page in the current theme, keeping its
/// hue: lifted on the dark page ([feedClassTextColor]), deepened on the light
/// one, and in both walked in lightness until it clears 4.5:1 on the page
/// background, so the yellow of an inaccuracy or the green of a best move
/// stays readable in either theme.
Color feedClassTextColorFor(BuildContext context, MoveClass moveClass) {
  final page = context.colors.background;
  final base = context.isLightTheme
      ? feedClassColor(moveClass)
      : feedClassTextColor(moveClass);
  return feedReadableOn(base, page);
}

/// WCAG contrast ratio between two opaque colours.
double feedContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [color] with its lightness walked away from [background] (darker on a
/// light page, lighter on a dark one) until it clears [target]:1, hue and
/// saturation kept. Unchanged when it already does.
Color feedReadableOn(Color color, Color background, {double target = 4.6}) {
  final opaque = color.withValues(alpha: 1);
  if (feedContrast(opaque, background) >= target) return opaque;
  final darken = background.computeLuminance() > 0.18;
  var hsl = HSLColor.fromColor(opaque);
  for (var i = 0; i < 50; i++) {
    final next = (hsl.lightness + (darken ? -0.02 : 0.02)).clamp(0.0, 1.0);
    hsl = hsl.withLightness(next);
    final candidate = hsl.toColor();
    if (feedContrast(candidate, background) >= target) return candidate;
    if (next == 0.0 || next == 1.0) return candidate;
  }
  return hsl.toColor();
}

/// "Brilliant", "Missed win", "Book".
String feedClassLabel(MoveClass moveClass) => switch (moveClass) {
  MoveClass.brilliant => 'Brilliant',
  MoveClass.great => 'Great move',
  MoveClass.best => 'Best move',
  MoveClass.interesting => 'Interesting',
  MoveClass.inaccuracy => 'Inaccuracy',
  MoveClass.mistake => 'Mistake',
  MoveClass.blunder => 'Blunder',
  MoveClass.missedWin => 'Missed win',
  MoveClass.book => 'Book move',
};

/// The glyph a notation token carries after its SAN (`!!`, `?`, `!?` …), or
/// null for the report-only verdicts (best, missed win, book), which the
/// board speaks for with its badge.
String? feedClassSuffix(MoveClass moveClass) => switch (moveClass) {
  MoveClass.brilliant ||
  MoveClass.great ||
  MoveClass.interesting ||
  MoveClass.inaccuracy ||
  MoveClass.mistake ||
  MoveClass.blunder => moveClass.glyph,
  _ => null,
};

/// Where a move's badge and landing go: the square the moving piece ends on.
///
/// Castling spelled king-takes-rook (e1h1, the game plies' and dartchess's
/// form) lands on the king's real square (g1). Whether a move is castling is
/// read from [before], the position it was played from: only a king taking
/// its own rook castles, so a rook or queen going e1-h1 still lands on h1.
/// Without [before] the destination is taken as written.
Square? feedLandingSquare(Move? move, Position? before) {
  if (move == null) return null;
  if (move is NormalMove) {
    return before == null ? move.to : standardMove(before, move).to;
  }
  final squares = move.squares.toList();
  return squares.isEmpty ? null : squares.last;
}

/// The classification mark itself at [size]: the badge SVG, or for `!?` the
/// glyph on a disc of its colour.
class FeedClassMark extends StatelessWidget {
  const FeedClassMark({required this.moveClass, required this.size, super.key});

  final MoveClass moveClass;
  final double size;

  @override
  Widget build(BuildContext context) {
    final type = feedAnnotationType(moveClass);
    if (type != null) {
      return SizedBox.square(
        dimension: size,
        child: SvgPicture.asset(
          moveAnnotationIconAsset(type),
          fit: BoxFit.contain,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: feedClassColor(moveClass),
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          moveClass.glyph,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1,
            fontSize: size * 0.62,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

/// The classification badge pinned to the top-right corner of a move's
/// destination square — the board screen's badge geometry — for use inside
/// a [Stack] that exactly covers a board of [boardSize].
///
/// Pops in on a spring each time [trigger] changes; appears settled when the
/// platform asks for reduced motion.
class FeedBoardBadge extends StatelessWidget {
  const FeedBoardBadge({
    required this.square,
    required this.moveClass,
    required this.boardSize,
    required this.orientation,
    required this.trigger,
    super.key,
  });

  final Square square;
  final MoveClass moveClass;
  final double boardSize;
  final Side orientation;
  final Object? trigger;

  @override
  Widget build(BuildContext context) {
    final squareSize = boardSize / 8;
    final flipped = orientation == Side.black;
    final file = flipped ? 7 - square.file : square.file;
    final row = flipped ? square.rank : 7 - square.rank;
    final isText = feedAnnotationType(moveClass) == null;
    final badge = squareSize * (isText ? 0.42 : 0.40);
    final left = (file * squareSize + squareSize - badge / 2).clamp(
      0.0,
      boardSize - badge,
    );
    final top = (row * squareSize - badge / 2 + squareSize * 0.04).clamp(
      0.0,
      boardSize - badge,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final mark = DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // A tight, one-light-source lift so the badge separates from the
        // square under it; never a halo.
        boxShadow: [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: FeedClassMark(moveClass: moveClass, size: badge),
    );

    return Positioned(
      left: left,
      top: top,
      width: badge,
      height: badge,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: reduceMotion
              ? mark
              : SingleMotionBuilder(
                  key: ValueKey(trigger),
                  from: 0.6,
                  value: 1,
                  motion: const CupertinoMotion.bouncy(),
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: mark,
                ),
        ),
      ),
    );
  }
}
