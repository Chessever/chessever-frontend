import 'package:dartchess/dartchess.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';

class PgnParseResult {
  final List<Move> allMoves;
  final List<String> moveSans;
  final Position startingPos;
  final Position finalPos;
  final Move? lastMove;
  final List<String> moveTimes;

  PgnParseResult({
    required this.allMoves,
    required this.moveSans,
    required this.startingPos,
    required this.finalPos,
    this.lastMove,
    required this.moveTimes,
  });
}

PgnParseResult parsePgnWorker(String pgn) {
  final gameData = PgnGame.parsePgn(pgn);
  final startingPos = PgnGame.startingPosition(gameData.headers);

  var tempPos = startingPos;
  final allMoves = <Move>[];
  final moveSans = <String>[];

  // Parse moves
  for (final node in gameData.moves.mainline()) {
    final move = tempPos.parseSan(node.san);
    if (move == null) break;
    allMoves.add(move);
    moveSans.add(node.san);
    tempPos = tempPos.play(move);
  }

  final finalPos = tempPos;
  final lastMove = allMoves.isNotEmpty ? allMoves.last : null;

  // Parse times
  final times = <String>[];

  try {
    for (final nodeData in gameData.moves.mainline()) {
      String? timeString;
      if (nodeData.comments != null) {
        for (String comment in nodeData.comments!) {
          timeString = extractPgnClockStringFromComment(comment);
          if (timeString != null) {
            break;
          }
        }
      }
      if (timeString != null) {
        times.add(formatPgnClockForDisplay(timeString));
      } else {
        times.add('-:--:--');
      }
    }
  } catch (e) {
    // Fallback if iteration fails
    try {
      for (final timeString in extractPgnClockStringsFromText(pgn)) {
        times.add(formatPgnClockForDisplay(timeString));
      }
    } catch (_) {}
  }

  return PgnParseResult(
    allMoves: allMoves,
    moveSans: moveSans,
    startingPos: startingPos,
    finalPos: finalPos,
    lastMove: lastMove,
    moveTimes: times,
  );
}
