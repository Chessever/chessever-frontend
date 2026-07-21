import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:dartchess/dartchess.dart';

final RegExp _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

/// Desktop `board_pane._pathFromPointer` — copied verbatim.
///
/// Walks [pointer] through [game] and returns the move list from the start
/// to the cursor (mainline + variation hops). This is the line desktop feeds
/// the opening explorer as `lineUcis`.
List<ChessMove> pathFromPointer(ChessGame game, ChessMovePointer pointer) {
  final path = <ChessMove>[];
  if (pointer.isEmpty) return path;

  ChessLine? currentList = game.mainline;
  ChessMove? currentMove;

  for (var i = 0; i < pointer.length; i++) {
    final index = pointer[i];

    if (i.isEven) {
      if (currentList == null || index >= currentList.length) break;
      path.addAll(currentList.take(index + 1));
      currentMove = currentList[index];
      if (i == pointer.length - 1) break;
    } else {
      if (currentMove == null ||
          currentMove.variations == null ||
          index >= currentMove.variations!.length) {
        break;
      }
      final variation = currentMove.variations![index];
      if (variation.isNotEmpty &&
          _fenSideToMove(variation.first.fen) ==
              _fenSideToMove(currentMove.fen)) {
        // Variation that *replaces* the parent move: both are the same side's
        // move, so their resulting positions share a side-to-move. Classify by
        // FEN, NOT `ChessMove.turn` — that field is inconsistent (PGN-parsed
        // moves store the mover, navigator-created moves store who is next), so
        // a *continuation* like 11.Be3 after 10...h6 compared equal and wrongly
        // dropped h6, producing a line that no longer replays to the board FEN.
        path.removeLast();
      }
      currentList = variation;
    }
  }
  return path;
}

/// Desktop board_pane formula:
/// `lineUcis = pathFromPointer(chessGame, pointer).map((m) => m.uci)`
///
/// Falls back to replaying [AnalysisBoardState.combinedMoves] only when the
/// analysis tree is missing (pre-init). Never truncates by flat index alone.
List<String> resolveExplorerMoveLine(AnalysisBoardState analysisState) {
  final targetFen = analysisState.position.fen;
  final game = analysisState.game;

  if (game != null) {
    // 1) Desktop primary path: pointer → fullMovePath
    final pathMoves = pathFromPointer(game, analysisState.movePointer);
    final pathUcis = _sanitizeUcis(pathMoves.map((m) => m.uci));
    if (pathUcis != null) {
      final nav = ChessGameNavigatorState(
        game: game,
        movePointer: analysisState.movePointer,
      );
      if (_samePosition(nav.currentFen, targetFen)) {
        return List<String>.unmodifiable(pathUcis);
      }
      // Pointer may lag: still accept path if it replays to the board FEN.
      if (_replaysToFen(game.startingFen, pathUcis, targetFen)) {
        return List<String>.unmodifiable(pathUcis);
      }
    }

    // 2) Mainline scan (live parse / pointer lag) — longest prefix to board FEN
    final mainlinePath = _mainlinePathReachingFen(game, targetFen);
    if (mainlinePath != null) {
      return mainlinePath;
    }
  }

  // 3) Flat history fallback (no game tree yet)
  final startingFen = resolveExplorerStartingFen(analysisState);
  return _linePrefixReachingFen(
    startingFen ?? Chess.initial.fen,
    analysisState.combinedMoves,
    targetFen,
  );
}

/// Start FEN for the explorer query — desktop uses `chessGame.startingFen`.
String? resolveExplorerStartingFen(AnalysisBoardState analysisState) {
  final fromGame = analysisState.game?.startingFen;
  if (fromGame != null && fromGame.trim().isNotEmpty) return fromGame;
  return analysisState.startingPosition?.fen;
}

/// True when [fen] is the standard initial position (first 4 fields).
bool isInitialExplorerFen(String? fen) {
  if (fen == null || fen.trim().isEmpty) return true;
  final a = fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
  final b = Chess.initial.fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
  return a == b;
}

List<String>? _mainlinePathReachingFen(ChessGame game, String targetFen) {
  if (game.mainline.isEmpty) {
    if (_samePosition(game.startingFen, targetFen)) return const <String>[];
    return null;
  }

  final path = <String>[];
  List<String>? best;
  for (final move in game.mainline) {
    final uci = move.uci.trim().toLowerCase();
    if (!_uciPattern.hasMatch(uci)) return best;
    path.add(uci);
    if (_sameExactFen(move.fen, targetFen)) {
      return List<String>.unmodifiable(List<String>.of(path));
    }
    if (_samePosition(move.fen, targetFen)) {
      best = List<String>.unmodifiable(List<String>.of(path));
    }
  }
  return best;
}

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
      var move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) {
        final alt = _alternateCastling(position, move);
        if (alt == null || !position.isLegal(alt)) return false;
        move = alt;
      }
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
    List<String>? exactMatch;
    List<String>? positionOnlyMatch;
    for (final rawMove in moves) {
      final uci = rawMove.uci.trim().toLowerCase();
      if (!_uciPattern.hasMatch(uci)) {
        return exactMatch ?? positionOnlyMatch ?? const <String>[];
      }
      var move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) {
        final alt = _alternateCastling(position, move);
        if (alt == null || !position.isLegal(alt)) {
          return exactMatch ?? positionOnlyMatch ?? const <String>[];
        }
        move = alt;
        path.add(alt.uci);
      } else {
        path.add(uci);
      }
      position = position.play(move);
      if (_sameExactFen(position.fen, targetFen)) {
        exactMatch = List<String>.unmodifiable(List<String>.of(path));
      } else if (_samePosition(position.fen, targetFen)) {
        positionOnlyMatch = List<String>.of(path);
      }
    }
    return exactMatch ??
        (positionOnlyMatch == null
            ? const <String>[]
            : List<String>.unmodifiable(positionOnlyMatch));
  } catch (_) {
    return const <String>[];
  }
}

NormalMove? _alternateCastling(Position position, NormalMove move) {
  final piece = position.board.pieceAt(move.from);
  if (piece == null || piece.role != Role.king) return null;
  const pairs = <String, String>{
    'e1h1': 'e1g1',
    'e1g1': 'e1h1',
    'e1a1': 'e1c1',
    'e1c1': 'e1a1',
    'e8h8': 'e8g8',
    'e8g8': 'e8h8',
    'e8a8': 'e8c8',
    'e8c8': 'e8a8',
  };
  final alt = pairs['${move.from.name}${move.to.name}'];
  if (alt == null) return null;
  return NormalMove.fromUci(alt);
}

/// Side to move in [fen] ('w' or 'b'); '' when malformed. Reliable across both
/// PGN-parsed and navigator-created moves, unlike [ChessMove.turn].
String _fenSideToMove(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.length > 1 ? parts[1] : '';
}

bool _sameExactFen(String left, String right) =>
    _fenKey(left, fieldCount: 6) == _fenKey(right, fieldCount: 6);

bool _samePosition(String left, String right) =>
    _fenKey(left, fieldCount: 4) == _fenKey(right, fieldCount: 4);

String _fenKey(String fen, {required int fieldCount}) =>
    fen.trim().split(RegExp(r'\s+')).take(fieldCount).join(' ');
