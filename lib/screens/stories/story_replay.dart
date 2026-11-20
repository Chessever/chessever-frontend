import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// What one game story's board shows while its bar fills.
///
/// The game (or its last [maxPlies] plies, from the position before them)
/// plays at one steady cadence inside the story's [windowStart] to
/// [windowEnd] share of its run, so the last move lands just before the
/// story ends and the final position holds, its move highlighted, for the
/// rest. A game without a playable PGN is a [StoryReplay.still]: its final
/// position for the whole story.
///
/// Every frame is read from the story's progress ([stepAt]), never from a
/// clock of its own, so a paused story holds its board and a test's fake
/// time drives it exactly.
@immutable
class StoryReplay {
  const StoryReplay._({required this.fens, required this.lastMoves});

  /// A board that does not move: [fen] (the start position when null) with
  /// [lastMove] highlighted.
  factory StoryReplay.still(String? fen, Move? lastMove) => StoryReplay._(
    fens: [fen == null || fen.trim().isEmpty ? Chess.initial.fen : fen],
    lastMoves: [lastMove],
  );

  /// The replay of [pgn]'s mainline, or null when it has no playable move.
  static StoryReplay? fromPgn(String? pgn) {
    if (pgn == null || pgn.trim().isEmpty) return null;
    final game = parseFlowPgn(pgn, maxPlies: 1000);
    if (game == null) return null;
    final moves = game.moves;
    final first = moves.length > maxPlies ? moves.length - maxPlies : 0;
    final fens = <String>[
      first == 0 ? game.start.fen : moves[first - 1].after.fen,
    ];
    final lastMoves = <Move?>[first == 0 ? null : moves[first - 1].move];
    for (var i = first; i < moves.length; i++) {
      fens.add(moves[i].after.fen);
      lastMoves.add(moves[i].move);
    }
    return StoryReplay._(
      fens: List.unmodifiable(fens),
      lastMoves: List.unmodifiable(lastMoves),
    );
  }

  /// At most this many plies are replayed: a longer game shows its finale.
  static const int maxPlies = 30;

  /// The share of the story before the first move plays: the opening
  /// position reads for a beat.
  static const double windowStart = 0.05;

  /// The share of the story by which every move has played.
  static const double windowEnd = 0.80;

  /// The share of the story at which a replayed game's outcome shows (its
  /// result, the fallen king): a beat after the last move lands, so the move
  /// is seen before the ending is marked on it.
  static const double revealAt = windowEnd + 0.04;

  /// Whether the outcome shows at story progress [t]. A board that does not
  /// move shows it from the start.
  bool revealedAt(double t) => !moves || t >= revealAt;

  /// The positions shown, in order: the one before the first replayed move,
  /// then one after each move.
  final List<String> fens;

  /// The move that led to each of [fens] (null for a game's very start).
  final List<Move?> lastMoves;

  /// How many moves play.
  int get plies => fens.length - 1;

  /// Whether the board moves at all.
  bool get moves => plies > 0;

  /// The step (an index into [fens]) shown at story progress [t], 0 to 1.
  /// Step 0 holds until [windowStart]; the first move plays there and each
  /// next one a cadence later; the last step holds to the end.
  int stepAt(double t) {
    if (plies == 0 || t < windowStart) return 0;
    final cadence = (windowEnd - windowStart) / plies;
    final step = 1 + ((t - windowStart) / cadence).floor();
    return step > plies ? plies : step;
  }
}
