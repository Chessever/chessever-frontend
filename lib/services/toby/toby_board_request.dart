/// What Toby reads for a board, and how a Toby reading becomes the board's
/// usual engine output (evaluation bar, engine lines, arrows).
///
/// Shared by every board feature that asks Toby about the position on
/// screen, so they build the same [TobyRequest] and therefore share one
/// reading loop and one cache entry per position ([tobyReadingCache]).
library;

import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_move_line.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:dartchess/dartchess.dart';

final RegExp _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

/// The request Toby reads for the position [state] shows, or null when Toby
/// cannot read it: threats mode (a null-move position, not a game state), a
/// non-standard variant, or a move line that does not replay to the board.
///
/// [targetFen] is the position to read; it defaults to the board's current
/// position (the analysis position in analysis mode).
///
/// The request carries the raw game facts and Gamebase derives Toby's inputs
/// from them: the players' ratings (the game's, else the PGN `WhiteElo` /
/// `BlackElo`), the PGN `TimeControl`, the event's speed label, and the PGN
/// `Site` and `Event` tags.
TobyRequest? buildTobyRequestFromBoardState(
  ChessBoardStateNew state, {
  String? targetFen,
}) {
  if (state.isThreatsMode) return null;
  final analysis = state.analysisState;
  final headers = analysis.game?.metadata ?? const <String, dynamic>{};
  String? header(String key) {
    final value = headers[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  if (!tobyReadsVariant(header('Variant'))) return null;

  final boardFen =
      targetFen ??
      (state.isAnalysisMode ? analysis.position.fen : state.position?.fen);
  if (boardFen == null) return null;

  final line = _lineToPosition(state, boardFen);
  if (line == null) return null;

  return TobyRequest(
    startFen: line.startFen,
    moves: line.moves,
    whiteRating: _rating(state.game.whitePlayer.rating, header('WhiteElo')),
    blackRating: _rating(state.game.blackPlayer.rating, header('BlackElo')),
    timeControl: header('TimeControl'),
    category: state.game.timeControl,
    site: header('Site'),
    event: header('Event'),
  );
}

int? _rating(int? gameRating, String? pgnElo) =>
    tobyRating(gameRating) ?? tobyRating(int.tryParse(pgnElo ?? ''));

/// The start position and UCI moves that reach [boardFen]: the analysis
/// line first (variations included), then the played mainline up to the
/// current move. Null when neither replays to the board.
({String startFen, List<String> moves})? _lineToPosition(
  ChessBoardStateNew state,
  String boardFen,
) {
  final analysis = state.analysisState;
  final candidates = <({String startFen, List<String> moves})>[];

  final analysisStart =
      resolveExplorerStartingFen(analysis) ?? Chess.initial.fen;
  candidates.add((
    startFen: analysisStart,
    moves: resolveExplorerMoveLine(analysis),
  ));

  final mainlineStart =
      state.startingPosition?.fen ??
      analysis.startingPosition?.fen ??
      analysisStart;
  final playedCount = math.min(
    state.currentMoveIndex + 1,
    state.allMoves.length,
  );
  if (playedCount >= 0) {
    candidates.add((
      startFen: mainlineStart,
      moves: [
        for (final move in state.allMoves.take(playedCount))
          move.uci.trim().toLowerCase(),
      ],
    ));
  }

  for (final candidate in candidates) {
    final moves = replayTobyLine(candidate.startFen, candidate.moves, boardFen);
    if (moves != null) return (startFen: candidate.startFen, moves: moves);
  }
  return null;
}

/// [moves] in Toby's form (castling as king to the g or c file) when they
/// replay from [startFen] to the position of [targetFen] (placement, side,
/// castling rights and en passant); otherwise null.
List<String>? replayTobyLine(
  String startFen,
  List<String> moves,
  String targetFen,
) {
  try {
    var position = Position.setupPosition(Rule.chess, Setup.parseFen(startFen));
    final out = <String>[];
    for (final raw in moves) {
      final uci = raw.trim().toLowerCase();
      if (!_uciPattern.hasMatch(uci)) return null;
      final parsed = Move.parse(uci);
      if (parsed == null) return null;
      final move = parsed is NormalMove
          ? position.normalizeMove(parsed)
          : parsed;
      if (!position.isLegal(move)) return null;
      out.add(tobyStyleUci(position, move));
      position = position.play(move);
    }
    return _samePosition(position.fen, targetFen) ? out : null;
  } catch (_) {
    return null;
  }
}

/// [move] in the UCI form Toby speaks: castling as the king's two-square
/// step (`e1g1`), not dartchess's king-takes-rook form (`e1h1`).
String tobyStyleUci(Position position, Move move) {
  final uci = move.uci;
  if (move is! NormalMove) return uci;
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  if (piece == null ||
      piece.role != Role.king ||
      target == null ||
      target.role != Role.rook ||
      target.color != piece.color) {
    return uci;
  }
  final from = uci.substring(0, 2);
  final kingside = uci.codeUnitAt(2) > uci.codeUnitAt(0);
  return '$from${kingside ? 'g' : 'c'}${from[1]}';
}

bool _samePosition(String left, String right) =>
    _fenKey(left) == _fenKey(right);

String _fenKey(String fen) =>
    fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

/// The pseudo evaluation, in pawns from White's side, whose evaluation-bar
/// fill equals White's expected score in [wdl] (win plus half the draws).
/// The bar maps pawns to its fill with a logistic of scale 3, so this is its
/// inverse. Held inside +-9.9 so the bar never takes it for a mate.
double tobyPseudoEvaluation(TobyWdl wdl) {
  const limit = 9.9;
  final expected = (wdl.white + wdl.draw / 2).clamp(0.0, 1.0);
  if (expected <= 0) return -limit;
  if (expected >= 1) return limit;
  final pawns = 3.0 * math.log(expected / (1 - expected));
  return pawns.clamp(-limit, limit).toDouble();
}

/// The chance a move is played as the engine line's badge shows it: a whole
/// percentage ("34%"), "<1%" for a positive chance that rounds to nothing.
String tobyEngineLineChance(double probability) {
  final percent = (probability.clamp(0.0, 1.0) * 100).round();
  if (percent == 0 && probability > 0) return '<1%';
  return '$percent%';
}

/// One engine line from a Toby candidate: the move, its pseudo evaluation in
/// centipawns from White's side (its own outcome in the final reading, the
/// position's in the network stage), and its badge text.
typedef TobyEngineLine = ({String uci, int whiteCp, String label});

/// The engine lines a [reading] fills, most likely first, at most [count].
List<TobyEngineLine> tobyEngineLines(TobyReading reading, int count) {
  final lines = <TobyEngineLine>[];
  for (final candidate in reading.candidates.take(math.max(0, count))) {
    final wdl = candidate.wdl ?? reading.positionWdl;
    final pawns = wdl == null ? 0.0 : tobyPseudoEvaluation(wdl);
    lines.add((
      uci: candidate.uci,
      whiteCp: (pawns * 100).round(),
      label: tobyEngineLineChance(candidate.probability),
    ));
  }
  return lines;
}
