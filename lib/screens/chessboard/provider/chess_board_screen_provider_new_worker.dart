import 'package:dartchess/dartchess.dart';

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
  String workerFormatDisplayTime(String timeString) {
    final parts = timeString.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = parts[1];
      final seconds = parts[2];
      if (hours == 0) {
        return '$minutes:$seconds';
      }
      return '$hours:$minutes:$seconds';
    }
    return timeString;
  }

  try {
    for (final nodeData in gameData.moves.mainline()) {
      String? timeString;
      if (nodeData.comments != null) {
        for (String comment in nodeData.comments!) {
          final timeMatch = RegExp(
            r'\[%clk (\d+:\d+:\d+)\]',
          ).firstMatch(comment);
          if (timeMatch != null) {
            timeString = timeMatch.group(1);
            break;
          }
        }
      }
      if (timeString != null) {
        times.add(workerFormatDisplayTime(timeString));
      } else {
        times.add('-:--:--');
      }
    }
  } catch (e) {
    // Fallback if iteration fails
    try {
      final regex = RegExp(r'\{ \[%clk (\d+:\d+:\d+)\] \}');
      final matches = regex.allMatches(pgn);
      for (final match in matches) {
        final timeString = match.group(1) ?? '0:00:00';
        times.add(workerFormatDisplayTime(timeString));
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
