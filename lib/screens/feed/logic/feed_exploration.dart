import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// One move the viewer played on a Feed board.
@immutable
class FeedExploreMove {
  const FeedExploreMove({
    required this.move,
    required this.san,
    required this.after,
  });

  /// Normalised (castling is king-to-rook, like the game's own plies).
  final Move move;
  final String san;
  final Position after;
}

/// The viewer's own line on a Feed board, forked from the game at
/// [forkPly]. Pure: every change returns a new line.
///
/// [cursor] is the move on the board: -1 for the fork position itself, else
/// an index into [moves]. Playing from an earlier cursor replaces what came
/// after it, the way a scratch line on a real board would.
@immutable
class FeedExploration {
  const FeedExploration({
    required this.forkPly,
    required this.start,
    this.moves = const [],
    this.cursor = -1,
  });

  /// The game ply the line branches from.
  final int forkPly;

  /// Position at [forkPly].
  final Position start;
  final List<FeedExploreMove> moves;
  final int cursor;

  Position get position => cursor < 0 ? start : moves[cursor].after;

  /// The move that produced [position]; null at the fork.
  FeedExploreMove? get current => cursor < 0 ? null : moves[cursor];

  bool get isEmpty => moves.isEmpty;

  /// Plays [move] from [position]. Null when it is not legal there.
  (FeedExploration, FeedExploreMove)? play(Move move) {
    final from = position;
    if (!from.isLegal(move)) return null;
    final normalized = move is NormalMove ? from.normalizeMove(move) : move;
    final (after, san) = from.makeSan(move);
    final played = FeedExploreMove(move: normalized, san: san, after: after);
    final kept = moves.sublist(0, cursor + 1);
    final line = FeedExploration(
      forkPly: forkPly,
      start: start,
      moves: List.unmodifiable([...kept, played]),
      cursor: kept.length,
    );
    return (line, played);
  }

  /// Shows move [index] of the line (-1 for the fork position).
  FeedExploration jumpTo(int index) => FeedExploration(
    forkPly: forkPly,
    start: start,
    moves: moves,
    cursor: index.clamp(-1, moves.length - 1),
  );

  /// "16. Qh5+" or "15... Nf6" for move [index] of the line.
  String labelAt(int index) {
    final blackFirst = start.turn == Side.black;
    final k = index + (blackFirst ? 1 : 0);
    final number = start.fullmoves + k ~/ 2;
    final san = moves[index].san;
    return k.isEven ? '$number. $san' : '$number... $san';
  }

  /// The number printed before move [index]: "16." for White, "15..." for
  /// Black when it opens the line, null for Black's reply.
  String? numberAt(int index) {
    final blackFirst = start.turn == Side.black;
    final k = index + (blackFirst ? 1 : 0);
    final number = start.fullmoves + k ~/ 2;
    if (k.isEven) return '$number.';
    return index == 0 ? '$number...' : null;
  }

  /// Whether move [index] of the line was White's.
  bool isWhiteAt(int index) {
    final blackFirst = start.turn == Side.black;
    return (index + (blackFirst ? 1 : 0)).isEven;
  }
}
