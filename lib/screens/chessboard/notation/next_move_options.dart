import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';

/// A candidate next move playable from the position identified by a
/// [ChessMovePointer]: either the current line's own continuation or the
/// head of a variation branching at this position.
class NextMoveOption {
  final ChessMovePointer pointer;
  final ChessMove move;
  final bool isLineContinuation;

  const NextMoveOption({
    required this.pointer,
    required this.move,
    required this.isLineContinuation,
  });
}

String? _sideToMove(String fen) {
  final parts = fen.split(' ');
  return parts.length > 1 ? parts[1] : null;
}

ChessLine? _lineForPointer(ChessGame game, ChessMovePointer pointer) {
  ChessLine? line = game.mainline;
  ChessMove? move;
  for (var i = 0; i < pointer.length; i++) {
    final index = pointer[i];
    if (i.isEven) {
      if (line == null || index >= line.length) {
        return null;
      }
      move = line[index];
    } else {
      final variations = move?.variations;
      if (variations == null || index >= variations.length) {
        return null;
      }
      line = variations[index];
    }
  }
  return line;
}

/// Enumerates every next move reachable from the position at [pointer],
/// own-line continuation first, then variation heads in notation order.
///
/// Variation attachment has two shapes in this game model (see
/// `fullMovePath` in chess_game_navigator.dart):
/// - variations of move X that branch AFTER X (the common case), and
/// - variations of move X that are alternatives TO X itself (alternatives
///   to the first move, live-game divergence). Those are playable from the
///   position BEFORE X, so here they surface as options of X's predecessor.
///
/// The two are told apart via FEN side-to-move rather than `ChessMove.turn`,
/// whose semantics differ between PGN-parsed and navigator-created moves.
List<NextMoveOption> nextMoveOptionsAt(
  ChessGame game,
  ChessMovePointer pointer,
) {
  final line = _lineForPointer(game, pointer);
  if (line == null || line.isEmpty) return const [];

  final index = pointer.isEmpty ? -1 : pointer.last.toInt();
  if (index >= line.length) return const [];
  final current = index >= 0 ? line[index] : null;

  final options = <NextMoveOption>[];
  final seenUcis = <String>{};

  void addOption(
    ChessMovePointer optionPointer,
    ChessMove move, {
    required bool isLineContinuation,
  }) {
    if (!seenUcis.add(move.uci)) return;
    options.add(
      NextMoveOption(
        pointer: optionPointer,
        move: move,
        isLineContinuation: isLineContinuation,
      ),
    );
  }

  if (index + 1 < line.length) {
    final next = line[index + 1];
    final nextPointer =
        pointer.isEmpty
            ? <Number>[0]
            : (List<Number>.of(pointer)..last = index + 1);
    addOption(nextPointer, next, isLineContinuation: true);

    // Same-mover variations of `next` replace `next` itself, so they start
    // from this position too.
    final nextVariations = next.variations ?? const <ChessLine>[];
    for (var v = 0; v < nextVariations.length; v++) {
      final variation = nextVariations[v];
      if (variation.isEmpty) continue;
      if (_sideToMove(variation.first.fen) == _sideToMove(next.fen)) {
        addOption(
          <Number>[...nextPointer, v, 0],
          variation.first,
          isLineContinuation: false,
        );
      }
    }
  }

  if (current != null) {
    // Opposite-mover variations of the current move branch after it.
    final variations = current.variations ?? const <ChessLine>[];
    for (var v = 0; v < variations.length; v++) {
      final variation = variations[v];
      if (variation.isEmpty) continue;
      if (_sideToMove(variation.first.fen) != _sideToMove(current.fen)) {
        addOption(
          <Number>[...pointer, v, 0],
          variation.first,
          isLineContinuation: false,
        );
      }
    }
  }

  return options;
}

/// Splits [items] into rows of at most [maxPerRow], balancing counts so the
/// last row is never disproportionately sparse (e.g. 5 -> 3+2, not 4+1).
List<List<T>> balanceIntoRows<T>(List<T> items, int maxPerRow) {
  if (items.isEmpty || maxPerRow <= 0) return const [];
  final rowCount = (items.length / maxPerRow).ceil();
  final base = items.length ~/ rowCount;
  final remainder = items.length % rowCount;

  final rows = <List<T>>[];
  var cursor = 0;
  for (var r = 0; r < rowCount; r++) {
    final size = base + (r < remainder ? 1 : 0);
    rows.add(items.sublist(cursor, cursor + size));
    cursor += size;
  }
  return rows;
}
