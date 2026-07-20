import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:dartchess/dartchess.dart';

final RegExp _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

/// Returns the active UCI line that reaches the position shown on the board.
///
/// The game-tree pointer is authoritative. [AnalysisBoardState.currentMoveIndex]
/// can briefly lag while live-game and navigator updates interleave, so using
/// it as the sole source can truncate a deep line by one ply. The backend then
/// rejects that line because it does not reach the requested FEN.
List<String> resolveExplorerMoveLine(AnalysisBoardState analysisState) {
  final targetFen = analysisState.position.fen;
  final game = analysisState.game;

  if (game != null) {
    final navigatorState = ChessGameNavigatorState(
      game: game,
      movePointer: analysisState.movePointer,
    );
    if (_samePosition(navigatorState.currentFen, targetFen)) {
      final path = _sanitizeUcis(
        navigatorState.fullMovePath.map((move) => move.uci),
      );
      if (path != null && _replaysToFen(game.startingFen, path, targetFen)) {
        return List<String>.unmodifiable(path);
      }
    }
  }

  // Fallback for transient states that do not yet expose a usable game tree.
  // Replay the available linear history and stop at the displayed FEN instead
  // of trusting a potentially stale flat index.
  final startingFen = resolveExplorerStartingFen(analysisState);
  return _linePrefixReachingFen(
    startingFen ?? Chess.initial.fen,
    analysisState.combinedMoves,
    targetFen,
  );
}

/// Returns the start position that owns [resolveExplorerMoveLine].
String? resolveExplorerStartingFen(AnalysisBoardState analysisState) =>
    analysisState.game?.startingFen ?? analysisState.startingPosition?.fen;

List<String>? _sanitizeUcis(Iterable<String> moves) {
  final sanitized = <String>[];
  for (final move in moves) {
    final uci = move.trim().toLowerCase();
    if (!_uciPattern.hasMatch(uci)) return null;
    sanitized.add(uci);
  }
  return sanitized;
}

bool _replaysToFen(String startingFen, List<String> moves, String targetFen) {
  try {
    var position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(startingFen),
    );
    for (final uci in moves) {
      final move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) return false;
      position = position.play(move);
    }
    return _samePosition(position.fen, targetFen);
  } catch (_) {
    return false;
  }
}

List<String> _linePrefixReachingFen(
  String startingFen,
  List<Move> moves,
  String targetFen,
) {
  try {
    var position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(startingFen),
    );
    if (_sameExactFen(position.fen, targetFen)) return const <String>[];

    final path = <String>[];
    List<String>? positionOnlyMatch;
    for (final rawMove in moves) {
      final uci = rawMove.uci.trim().toLowerCase();
      if (!_uciPattern.hasMatch(uci)) return const <String>[];

      final move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) return const <String>[];
      position = position.play(move);
      path.add(uci);

      if (_sameExactFen(position.fen, targetFen)) {
        return List<String>.unmodifiable(path);
      }
      if (_samePosition(position.fen, targetFen)) {
        positionOnlyMatch = List<String>.of(path);
      }
    }

    return positionOnlyMatch == null
        ? const <String>[]
        : List<String>.unmodifiable(positionOnlyMatch);
  } catch (_) {
    return const <String>[];
  }
}

bool _sameExactFen(String left, String right) =>
    _fenKey(left, fieldCount: 6) == _fenKey(right, fieldCount: 6);

bool _samePosition(String left, String right) =>
    _fenKey(left, fieldCount: 4) == _fenKey(right, fieldCount: 4);

String _fenKey(String fen, {required int fieldCount}) =>
    fen.trim().split(RegExp(r'\s+')).take(fieldCount).join(' ');
