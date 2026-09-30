import 'package:dartchess/dartchess.dart';

/// Chess plumbing for race boards: positions from the room's UCI lines.
/// Nothing here judges a move; the room does.

/// The position of [fen], or null when it does not parse.
Position? raceParseFen(String fen) {
  try {
    return Chess.fromSetup(Setup.parseFen(fen));
  } catch (_) {
    return null;
  }
}

/// [uci] as a legal move in [position], castling in either spelling; null
/// when it is not one. A pawn step onto the last rank must name its piece.
NormalMove? raceLegalMove(Position position, String uci) {
  final move = Move.parse(uci);
  if (move is! NormalMove) return null;
  if (move.promotion == null &&
      position.board.pawns.has(move.from) &&
      SquareSet.backranks.has(move.to)) {
    return null;
  }
  if (!position.isLegal(move)) return null;
  return move;
}

/// [move] with castling spelled king-two-squares (e1g1), the way the room
/// reads it and the board highlights it, rather than king-takes-rook (e1h1).
NormalMove raceStandardMove(Position position, NormalMove move) {
  if (move.promotion != null) return move;
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  if (piece == null ||
      piece.role != Role.king ||
      target == null ||
      target.color != piece.color ||
      target.role != Role.rook) {
    return move;
  }
  final file = move.to.file > move.from.file ? File.g : File.c;
  return NormalMove(
    from: move.from,
    to: Square.fromCoords(file, move.from.rank),
  );
}

/// One played step: the move as the board shows it, its SAN and the
/// position after it.
typedef RaceStep = ({NormalMove move, String san, Position after});

/// Plays [uci] in [position]; null when it is not legal there.
RaceStep? racePlay(Position position, String uci) {
  final move = raceLegalMove(position, uci);
  if (move == null) return null;
  final (after, san) = position.makeSan(move);
  return (move: raceStandardMove(position, move), san: san, after: after);
}

/// The board after [fen]'s setup move and then [line]. Stops at the first
/// move that does not play. Returns the position, the last move and the
/// number of moves of [line] that played.
({Position position, NormalMove? lastMove, int played}) raceReplay(
  Position start,
  String setupMove,
  List<String> line,
) {
  var position = start;
  NormalMove? last;
  final setup = racePlay(position, setupMove);
  if (setup == null) return (position: position, lastMove: null, played: 0);
  position = setup.after;
  last = setup.move;
  var played = 0;
  for (final uci in line) {
    final step = racePlay(position, uci);
    if (step == null) break;
    position = step.after;
    last = step.move;
    played += 1;
  }
  return (position: position, lastMove: last, played: played);
}

/// [line] (the moves after the setup move) in SAN with move numbers:
/// "31. Qxh7+ Kxh7 32. Rh3#". Falls back to the UCI strings when the
/// position does not parse.
String raceSanLine(String fen, String setupMove, List<String> line) {
  final start = raceParseFen(fen);
  if (start == null) return line.join(' ');
  final setup = racePlay(start, setupMove);
  if (setup == null) return line.join(' ');
  var position = setup.after;
  final parts = <String>[];
  for (var i = 0; i < line.length; i++) {
    final step = racePlay(position, line[i]);
    if (step == null) {
      parts.addAll(line.skip(i));
      break;
    }
    final number = position.fullmoves;
    if (position.turn == Side.white) {
      parts.add('$number. ${step.san}');
    } else if (i == 0) {
      parts.add('$number... ${step.san}');
    } else {
      parts.add(step.san);
    }
    position = step.after;
  }
  return parts.join(' ');
}
