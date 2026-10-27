import 'package:dartchess/dartchess.dart';

class WatchReplayPosition {
  const WatchReplayPosition(this.fen, this.label, [this.lastMove]);
  final String fen;
  final String label;
  final String? lastMove;
}

/// A small, immutable snapshot. Live updates never move the position being
/// reviewed. Ignore variations, respect FEN starts, and reject illegal history.
List<WatchReplayPosition> watchReplayPositions(String? pgn) {
  if (pgn == null || pgn.trim().isEmpty || pgn.length > 262144) return [];
  try {
    final game = PgnGame.parsePgn(pgn);
    var position = PgnGame.startingPosition(game.headers);
    final positions = [WatchReplayPosition(position.fen, 'Start position')];
    for (final node in game.moves.mainline()) {
      if (positions.length > 512) return [];
      final move = position.parseSan(node.san);
      if (move == null) return [];
      final label =
          '${position.fullmoves}'
          '${position.turn == Side.white ? '.' : '…'} ${node.san}';
      position = position.play(move);
      positions.add(WatchReplayPosition(position.fen, label, move.uci));
    }
    return positions.length > 1 ? positions : [];
  } catch (_) {
    return [];
  }
}

/// A deliberate detent, not one move per display frame. Clear fractional
/// travel at each end so reversing the Crown responds immediately.
class WatchReplayDial {
  double _travel = 0;
  static const detent = 0.25;

  void reset() => _travel = 0;

  int turn(double delta, {required int index, required int last}) {
    if (!delta.isFinite) return index;
    if ((_travel > 0 && delta < 0) || (_travel < 0 && delta > 0)) reset();
    _travel += delta;
    final steps = (_travel / detent).truncate();
    if (steps == 0) return index;
    _travel -= steps * detent;
    final next = (index + steps).clamp(0, last);
    if (next == 0 || next == last) reset();
    return next;
  }
}
