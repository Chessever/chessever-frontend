import 'package:chessever2/screens/chessboard/utils/pgn_comment_annotations.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart'
    show NagCategory, getNagDisplay, nagShownAsText;
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessground/chessground.dart' show Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// What the line under a game story's board says about one move: its number
/// and SAN, the annotator's glyphs, their words, and the arrows and marked
/// squares they drew for it.
@immutable
class StoryMoveNote {
  const StoryMoveNote({
    required this.san,
    required this.moveNumber,
    required this.white,
    this.nags = const <int>[],
    this.comment,
    this.shapes = const <Shape>{},
  });

  final String san;
  final int moveNumber;

  /// White played it.
  final bool white;

  /// The glyphs printed after the SAN (`!`, `?!`, `±`), move-quality ones
  /// first. Never ChessEver's report codes, which only ever draw as badges.
  final List<int> nags;

  /// The annotator's words, every command (`[%clk]`, `[%cal]`, ...) gone.
  final String? comment;

  /// The move's `[%cal]` arrows and `[%csl]` squares.
  final Set<Shape> shapes;

  /// "23." for White's move, "23…" for Black's.
  String get number => white ? '$moveNumber.' : '$moveNumber…';

  /// Whether the annotator said anything about this move: the story dwells
  /// on it long enough to read.
  bool get annotated => comment != null || nags.isNotEmpty || shapes.isNotEmpty;

  /// The same move with only its number, SAN and glyphs: the move a replay
  /// opens on, already played, whose words belong to the moment before.
  StoryMoveNote get bare =>
      StoryMoveNote(san: san, moveNumber: moveNumber, white: white, nags: nags);
}

/// What one game story's board shows while its bar fills.
///
/// A game without annotations plays its last [maxPlies] plies (or all of
/// them) at one steady cadence inside the story's [windowStart] to
/// [windowEnd] share of a fixed run, so the last move lands just before the
/// story ends and the final position holds, its move highlighted, for the
/// rest. A game without a playable PGN is a [StoryReplay.still]: its final
/// position for the whole story.
///
/// An annotated game (comments, glyphs, arrows) plays on a schedule instead
/// ([scheduledDuration]): a steady cadence that slows into each annotated
/// move and dwells on it long enough to read its words, the story running
/// exactly as long as that schedule ([maxScheduled] at most). A long quiet
/// stretch is cut to the moves around its moments, the board jumping over
/// the rest; a game with more moments than fit shows the run that holds
/// the most of them, then its result.
///
/// Every frame is read from the story's progress ([stepAt]), never from a
/// clock of its own, so a paused story holds its board and a test's fake
/// time drives it exactly.
@immutable
class StoryReplay {
  const StoryReplay._({
    required this.fens,
    required this.lastMoves,
    this.notes = const [],
    this._starts,
    this._total = 0,
    this._revealTime = 0,
  });

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
    final notes = [for (final move in game.moves) _noteOf(move)];
    if (notes.any((note) => note.annotated)) {
      return _scheduled(game, notes);
    }
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

  static StoryMoveNote _noteOf(FeedPgnMove move) {
    final glyphs = [
      for (final nag in move.nags)
        if (nagShownAsText(nag) && getNagDisplay(nag) != null) nag,
    ];
    // Move-quality glyphs read first, as the notation prints them.
    final quality = [
      for (final nag in glyphs)
        if (getNagDisplay(nag)!.category == NagCategory.quality) nag,
    ];
    return StoryMoveNote(
      san: move.san,
      moveNumber: move.before.fullmoves,
      white: move.mover == Side.white,
      nags: List.unmodifiable({...quality, ...glyphs}),
      comment: pgnCommentProse(move.comments),
      shapes: Set.unmodifiable(pgnCommentShapes(move.comments)),
    );
  }

  // --------------------------------------------------- annotated schedule

  /// Seconds the opening position reads before the first move plays.
  static const double leadIn = 0.6;

  /// Seconds between plain moves far from any annotated one.
  static const double transitBeat = 0.22;

  /// Seconds between the moves leading into an annotated one, and the
  /// game's last few: the replay slows so the moment is seen coming. A
  /// position the board jumps to (over a cut stretch) holds as long.
  static const double approachBeat = 0.55;

  /// How many plies before an annotated move (and before the end) play at
  /// [approachBeat].
  static const int approachPlies = 2;

  /// An annotated move holds at least this long, plus [readPerChar] for
  /// each character of its words, up to [noteMax]: about 17 characters a
  /// second, a read rather than a skim. The cap is what the notes' four
  /// lines hold, so no move holds for words the reader cannot see.
  static const double noteBase = 1.4;
  static const double readPerChar = 0.055;
  static const double noteMax = 12;

  /// A run of plain moves longer than this (between two annotated moves,
  /// before the first, or after the last) is cut: the replay plays the
  /// [followPlies] after the moment before it and the [leadPlies] into the
  /// moment after it (or into the game's end), and the board jumps over
  /// the rest. A quiet stretch never eats the time the notes need.
  static const int stretchMax = 12;
  static const int followPlies = 2;
  static const int leadPlies = 6;

  /// Seconds the final position holds after the last move, at least: a
  /// note on the last move holds it as long as any other note.
  static const double tail = 1.8;

  /// Seconds after the last move lands that the outcome shows.
  static const double revealDelay = 0.35;

  /// An annotated story runs at most this long, and never shorter than
  /// [minScheduled].
  static const double maxScheduled = 35;
  static const double minScheduled = 8;

  /// How long annotated move [note] holds the board.
  static double dwellOf(StoryMoveNote note) {
    final words = note.comment?.length ?? 0;
    final dwell = noteBase + readPerChar * words;
    return dwell > noteMax ? noteMax : dwell;
  }

  /// The plies (1-based) an annotated replay may show: every annotated
  /// one, and the plain ones around them, a long plain stretch cut to the
  /// moves after the moment before it and the moves into the one after.
  /// Always ends on the game's last ply.
  static List<int> _keptPlies(List<StoryMoveNote> notes) {
    final n = notes.length;
    final kept = <int>[];
    var from = 1;
    void stretch(int first, int last, {required bool afterMoment}) {
      // Plain plies [first, last], then a moment (or the game's end).
      final length = last - first + 1;
      if (length <= 0) return;
      if (length <= stretchMax) {
        for (var i = first; i <= last; i++) {
          kept.add(i);
        }
        return;
      }
      if (afterMoment) {
        for (var i = first; i < first + followPlies; i++) {
          kept.add(i);
        }
      }
      for (var i = last - leadPlies + 1; i <= last; i++) {
        kept.add(i);
      }
    }

    for (var i = 1; i <= n; i++) {
      if (!notes[i - 1].annotated) continue;
      stretch(from, i - 1, afterMoment: from > 1);
      kept.add(i);
      from = i + 1;
    }
    if (from <= n) {
      // The plain run to the end: its last moves lead into the result.
      final length = n - from + 1;
      if (length <= stretchMax) {
        for (var i = from; i <= n; i++) {
          kept.add(i);
        }
      } else {
        for (var i = from; i < from + followPlies; i++) {
          kept.add(i);
        }
        for (var i = n - leadPlies + 1; i <= n; i++) {
          kept.add(i);
        }
      }
    }
    return kept;
  }

  /// How long the board holds each of [steps] (plies, in order, the last
  /// one the game's end): the end as long as its note needs, an annotated
  /// move its dwell, the moves into a moment or the end and a position
  /// jumped to at [approachBeat], the rest at [transitBeat].
  static List<double> _holdsOf(List<int> steps, List<StoryMoveNote> notes) {
    final n = notes.length;
    final last = steps.length - 1;
    final holds = <double>[];
    for (var j = 0; j <= last; j++) {
      final ply = steps[j];
      final note = notes[ply - 1];
      if (j == last) {
        final dwell = ply == n && note.annotated ? dwellOf(note) : 0.0;
        holds.add(dwell > tail ? dwell : tail);
        continue;
      }
      if (note.annotated) {
        holds.add(dwellOf(note));
        continue;
      }
      // Landed on after a cut: the new position reads for a beat.
      var hold = j > 0 && steps[j - 1] != ply - 1 ? approachBeat : transitBeat;
      for (var k = j + 1; k <= last && k <= j + approachPlies; k++) {
        if (k == last || notes[steps[k] - 1].annotated) hold = approachBeat;
      }
      holds.add(hold);
    }
    return holds;
  }

  /// The plies an annotated replay shows: of [kept], the run holding the
  /// most annotated moves that fits [maxScheduled], then (when that run
  /// stops short of the end) the game's last move, the board jumping to
  /// the result. Ties go to a run that reaches the end on its own, then to
  /// the longer one. A game whose notes come early keeps them; its quiet
  /// ending is a few moves and the result, never most of the story.
  static List<int> _window(List<int> kept, List<StoryMoveNote> notes) {
    final m = kept.length;
    final holds = _holdsOf(kept, notes);
    final finalHold = holds[m - 1];
    // Prefix sums of the holds and of the annotated moves.
    final time = List<double>.filled(m + 1, 0);
    final moments = List<int>.filled(m + 1, 0);
    for (var j = 0; j < m; j++) {
      time[j + 1] = time[j] + holds[j];
      moments[j + 1] = moments[j] + (notes[kept[j] - 1].annotated ? 1 : 0);
    }
    final endMoment = notes[kept[m - 1] - 1].annotated ? 1 : 0;
    // Steps p..q, and the game's end after them when q stops short.
    double cost(int p, int q) =>
        leadIn + time[q + 1] - time[p] + (q < m - 1 ? finalHold : 0);
    int score(int p, int q) =>
        moments[q + 1] - moments[p] + (q < m - 1 ? endMoment : 0);

    // The game's last run of moves with no cut in it: a run stopping inside
    // it would jump the board over a move or two before the result. Stopping
    // short of the end is only ever at a cut, where the board jumps anyway.
    var lastRun = m - 1;
    while (lastRun > 0 && kept[lastRun - 1] == kept[lastRun] - 1) {
      lastRun--;
    }

    var bestP = m - 1;
    var bestQ = m - 1;
    var bestScore = score(m - 1, m - 1);
    var reach = -1;
    for (var p = 0; p < m; p++) {
      if (reach < p - 1) reach = p - 1;
      while (reach + 1 < m && cost(p, reach + 1) <= maxScheduled) {
        reach++;
      }
      final q = reach == m - 1 || reach < lastRun ? reach : lastRun - 1;
      if (q < p) continue;
      final s = score(p, q);
      final reaches = q == m - 1;
      final bestReaches = bestQ == m - 1;
      final better =
          s > bestScore ||
          (s == bestScore && reaches && !bestReaches) ||
          (s == bestScore && reaches == bestReaches && q - p > bestQ - bestP);
      if (better) {
        bestP = p;
        bestQ = q;
        bestScore = s;
      }
    }
    return [
      for (var j = bestP; j <= bestQ; j++) kept[j],
      if (bestQ < m - 1) kept[m - 1],
    ];
  }

  static StoryReplay _scheduled(FeedPgnGame game, List<StoryMoveNote> notes) {
    var steps = _window(_keptPlies(notes), notes);
    while (true) {
      final replay = _build(game, notes, steps);
      // The window was chosen on the holds of the whole kept run; its own
      // edges can hold a beat longer. Never past the cap: a step goes from
      // its start until it fits.
      if (replay._total <= maxScheduled + 1e-9 || steps.length <= 1) {
        return replay;
      }
      steps = steps.sublist(1);
    }
  }

  /// The replay of [steps] (plies, in order): it opens on the position
  /// before the first of them, and each step after shows the position
  /// after its ply, the board jumping where plies were cut between them.
  static StoryReplay _build(
    FeedPgnGame game,
    List<StoryMoveNote> notes,
    List<int> steps,
  ) {
    final moves = game.moves;
    final first = steps.first;
    final fens = <String>[
      first == 1 ? game.start.fen : moves[first - 2].after.fen,
    ];
    final lastMoves = <Move?>[first == 1 ? null : moves[first - 2].move];
    final stepNotes = <StoryMoveNote?>[
      first == 1 ? null : notes[first - 2].bare,
    ];
    for (final ply in steps) {
      fens.add(moves[ply - 1].after.fen);
      lastMoves.add(moves[ply - 1].move);
      stepNotes.add(notes[ply - 1]);
    }
    final holds = _holdsOf(steps, notes);
    var lead = leadIn;
    var end = holds.last;
    var total = leadIn + holds.fold<double>(0, (sum, h) => sum + h);
    // A short game holds its opening and its end a little longer, never its
    // moves out of step.
    if (total < minScheduled) {
      final missing = minScheduled - total;
      lead += missing * 0.3;
      end += missing * 0.7;
    }
    final starts = <double>[0, lead];
    for (var j = 0; j < holds.length - 1; j++) {
      starts.add(starts.last + holds[j]);
    }
    // The schedule's sum, to the last hold: the bar ends as the hold does.
    total = starts.last + end;
    return StoryReplay._(
      fens: List.unmodifiable(fens),
      lastMoves: List.unmodifiable(lastMoves),
      notes: List.unmodifiable(stepNotes),
      starts: List.unmodifiable(starts),
      total: total,
      revealTime: starts.last + revealDelay,
    );
  }

  // -------------------------------------------------------------- plain

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

  // --------------------------------------------------------------- reads

  /// The positions shown, in order: the one before the first replayed move,
  /// then one after each move.
  final List<String> fens;

  /// The move that led to each of [fens] (null for a game's very start).
  final List<Move?> lastMoves;

  /// One per step of an annotated replay: the move that led to it, as the
  /// line under the board reads it (null for a game's very start). Empty
  /// for a game without annotations, which keeps its plain replay.
  final List<StoryMoveNote?> notes;

  /// Seconds into the story at which each step shows, on an annotated
  /// replay's schedule.
  final List<double>? _starts;
  final double _total;
  final double _revealTime;

  /// How many moves play.
  int get plies => fens.length - 1;

  /// Whether the board moves at all.
  bool get moves => plies > 0;

  /// Whether this replay runs on its annotations' schedule.
  bool get annotated => _starts != null;

  /// How long an annotated replay's story runs: its schedule's total. Null
  /// for a plain replay, which fills the stories' standard run.
  Duration? get scheduledDuration => annotated
      ? Duration(
          microseconds: (_total * Duration.microsecondsPerSecond).round(),
        )
      : null;

  /// The share of the story at which the outcome shows.
  double get revealShare => annotated ? _revealTime / _total : revealAt;

  /// The share of the story at which step [step] shows.
  double startOf(int step) {
    final starts = _starts;
    if (starts != null) return starts[step] / _total;
    if (step <= 0 || plies == 0) return 0;
    return windowStart + (step - 1) * (windowEnd - windowStart) / plies;
  }

  /// What the line under the board says at step [step]; null when the game
  /// carries no annotations.
  StoryMoveNote? noteAt(int step) =>
      notes.isEmpty || step < 0 || step >= notes.length ? null : notes[step];

  /// Whether the outcome shows at story progress [t]. A board that does not
  /// move shows it from the start.
  bool revealedAt(double t) => !moves || t >= revealShare;

  /// The step (an index into [fens]) shown at story progress [t], 0 to 1.
  /// Step 0 holds until the first move plays; each next one follows the
  /// cadence (or the schedule); the last step holds to the end.
  int stepAt(double t) {
    if (plies == 0) return 0;
    final starts = _starts;
    if (starts != null) {
      final time = t * _total;
      // The last step whose start has come.
      var low = 0;
      var high = starts.length - 1;
      while (low < high) {
        final mid = (low + high + 1) >> 1;
        if (starts[mid] <= time) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      return low;
    }
    if (t < windowStart) return 0;
    final cadence = (windowEnd - windowStart) / plies;
    final step = 1 + ((t - windowStart) / cadence).floor();
    return step > plies ? plies : step;
  }
}
