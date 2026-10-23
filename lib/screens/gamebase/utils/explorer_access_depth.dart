import 'dart:math' as math;

/// Plies a reader without Premium may play into the Opening Explorer: the
/// whole 10th move, White's and Black's. Positions after it are Premium, and
/// so is the step that would reach one.
const int kFreeExplorerMaxPly = 20;

/// Whether the Explorer at [ply] plies played needs Premium to be read.
bool explorerPlyLocked(int ply) => ply > kFreeExplorerMaxPly;

/// Whether one more ply from [ply] lands on a position that needs Premium.
bool explorerNextStepLocked(int ply) => ply >= kFreeExplorerMaxPly;

/// Explorer depth Premium access is measured at, in plies played.
///
/// [treePly] is the explorer's own depth: its move tree plus the offset a
/// session started from a FEN carries. That alone is not enough to hold the
/// line. It collapses to 0 when a tree rebuild drops the line, and a position
/// set up in the Board Editor, pasted, or deep-linked arrives at whatever
/// depth its counters claim, often move 1. So the depth is also floored by
/// what [fen] says itself: its fullmove counter, and the fewest plies any game
/// needs to reach its pieces ([explorerMinimumPliesToReach]). Every floor is
/// at most the real depth of a position reached by play, so a position
/// within the first 10 moves is never locked.
int explorerAccessPly({required int treePly, required String fen}) {
  return math.max(
    treePly,
    math.max(_pliesFromFenCounters(fen), explorerMinimumPliesToReach(fen)),
  );
}

/// The fewest plies any game needs to reach [fen]'s pieces from a standard or
/// Chess960 start, where every pawn stands on its second rank and every other
/// unit on its first.
///
/// A lower bound read from the board alone, so it holds whatever the FEN's
/// counters say:
/// * a pawn on its 3rd or 4th rank moved at least once, and one further up
///   once per rank past the 4th (a double step covers two ranks once);
/// * any other unit off its back rank moved at least once;
/// * every missing unit was captured, each by a move of the other side.
/// One move moves one unit, so the first two add up per side; captures can
/// be those same moves, so they only raise the total to their own count.
///
/// White moves first, so W White moves and B Black moves need at least
/// `max(2W - 1, 2B)` plies, rounded up to the parity of the side to move.
/// Returns 0 for anything that is not a readable board.
int explorerMinimumPliesToReach(String fen) {
  final fields = fen.trim().split(RegExp(r'\s+'));
  final rows = fields.first.split('/');
  if (rows.length != 8) return 0;

  var whiteMoves = 0;
  var blackMoves = 0;
  var whiteUnits = 0;
  var blackUnits = 0;
  for (var row = 0; row < 8; row++) {
    final rank = 8 - row;
    for (final symbol in rows[row].split('')) {
      if (int.tryParse(symbol) != null) continue;
      final piece = symbol.toLowerCase();
      if (!'pnbrqk'.contains(piece)) return 0;
      if (symbol != piece) {
        whiteUnits++;
        whiteMoves += piece == 'p' ? _pawnMoves(rank) : (rank == 1 ? 0 : 1);
      } else {
        blackUnits++;
        blackMoves += piece == 'p' ? _pawnMoves(9 - rank) : (rank == 8 ? 0 : 1);
      }
    }
  }
  whiteMoves = math.max(whiteMoves, 16 - blackUnits);
  blackMoves = math.max(blackMoves, 16 - whiteUnits);

  var plies = math.max(math.max(2 * whiteMoves - 1, 2 * blackMoves), 0);
  final blackToMove = fields.length > 1 && fields[1] == 'b';
  if (plies.isOdd != blackToMove) plies++;
  return plies;
}

/// Fewest moves a pawn standing on [relativeRank] (its own side's count, 2 is
/// home) needs.
int _pawnMoves(int relativeRank) {
  if (relativeRank <= 2) return 0;
  if (relativeRank <= 4) return 1;
  return relativeRank - 3;
}

/// Plies played according to [fen]'s fullmove counter and side to move.
int _pliesFromFenCounters(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 6) return 0;
  final fullMove = int.tryParse(parts[5]) ?? 1;
  final plies = (fullMove - 1) * 2 + (parts[1] == 'b' ? 1 : 0);
  return plies < 0 ? 0 : plies;
}
