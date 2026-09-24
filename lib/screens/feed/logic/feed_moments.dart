import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart'
    show GameMoveClassification;
import 'package:chessever2/screens/chessboard/game_review/lichess_judgment.dart';
import 'package:chessever2/screens/chessboard/game_review/move_position_facts.dart';
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// Critical-moment detection for Feed clips, with no engine at runtime.
///
/// Evidence, strongest first:
/// 1. **Report classifications** — the `$240`–`$247` NAG block a prewarmed
///    Game Analysis report baked into the PGN. When a game carries any of
///    them the report owns every verdict, exactly as it does on the board, so
///    a move it left unlabelled is not re-judged from its eval.
/// 2. **Standard glyph NAGs** (`!!`, `??`, `?`, `?!`) — lichess-analysed PGNs
///    carry these alongside `[%eval]`.
/// 3. **Eval swings** from `[%eval]`, judged by the verbatim lichess port
///    ([lichessAdvice]) so a Feed "Blunder" is the same call lichess makes.
/// 4. **Board heuristics** built on `move_position_facts.dart`: sacrifices,
///    promotions, checks, value-weighted captures, castling.
///
/// Mate on the board beats all of them. At most [kFlowMaxHeadlines] moments
/// per game stay at severity 3 — the rest are demoted to 2 — so a clip lingers
/// on its turning points instead of stuttering through every one.

/// Headline (severity 3) moments kept per game.
const int kFlowMaxHeadlines = 3;

/// Net material, in pawns, a move must give away to count as a sacrifice.
const int kFlowSacrificeMinMaterial = 3;

/// lichess judges move one against a fixed +0.15 (`Info.start`).
const EngineScore _initialPositionScore = CpScore(15);

/// A PGN carries the score after each move but never the engine's best move,
/// so [lichessAdvice]'s "the engine's own choice is never an error" gate has
/// nothing to compare against. This sentinel never equals a played UCI, which
/// makes the gate open and the verdict rest on the eval swing alone — a move
/// whose eval did not drop is never judged either way.
const String _unknownBestMove = '';

/// A parsed game, ready for the feed: plies with moments plus the facts the
/// feed ranks and captions on.
@immutable
class FeedClip {
  const FeedClip({
    required this.plies,
    required this.result,
    required this.hasEvals,
    required this.headlines,
    this.event,
  });

  final List<FeedPly> plies;

  /// The PGN's `[Event]`, when it names one.
  final String? event;

  /// `1-0`, `0-1`, `½-½` or null when unfinished / unknown.
  final String? result;
  final bool hasEvals;

  /// Types of the severity-3 moments, in ply order.
  final List<FeedMomentType> headlines;

  int get plyCount => plies.length - 1;

  /// Mate, a brilliancy or a sacrifice — the moments that make a clip.
  bool get hasBrilliance => headlines.any(
    (type) =>
        type == FeedMomentType.checkmate ||
        type == FeedMomentType.brilliant ||
        type == FeedMomentType.sacrifice,
  );

  bool get hasDrama => headlines.any(
    (type) =>
        type == FeedMomentType.blunder || type == FeedMomentType.missedWin,
  );
}

/// Parses [pgn] and detects its moments. Null when the PGN has no playable
/// mainline. Pure and synchronous, so it can run inside `Isolate.run`.
FeedClip? feedClipFromPgn(String pgn, {int maxHeadlines = kFlowMaxHeadlines}) {
  final game = parseFlowPgn(pgn);
  if (game == null) return null;
  final plies = buildFlowPlies(game, maxHeadlines: maxHeadlines);
  final event = game.headers['Event']?.trim();
  return FeedClip(
    plies: plies,
    event: event == null || event.isEmpty || event == '?' ? null : event,
    result: game.result,
    hasEvals: game.hasEvals,
    headlines: [
      for (final ply in plies)
        if (ply.moment?.isHeadline ?? false) ply.moment!.type,
    ],
  );
}

/// Index 0 is the start position; index `n` is the position after ply `n`.
List<FeedPly> buildFlowPlies(
  FeedPgnGame game, {
  int maxHeadlines = kFlowMaxHeadlines,
}) {
  final moments = detectFlowMoments(game, maxHeadlines: maxHeadlines);
  return List.unmodifiable(<FeedPly>[
    FeedPly(fen: game.start.fen),
    for (var i = 0; i < game.moves.length; i++)
      FeedPly(
        fen: game.moves[i].after.fen,
        san: game.moves[i].san,
        uci: game.moves[i].uci,
        cp: game.moves[i].cp,
        mate: game.moves[i].mate,
        moment: moments[i],
        moveClass: game.moves[i].moveClass,
      ),
  ]);
}

/// One moment (or null) per move of [game], aligned with [FeedPgnGame.moves].
List<FeedMoment?> detectFlowMoments(
  FeedPgnGame game, {
  int maxHeadlines = kFlowMaxHeadlines,
}) {
  final moves = game.moves;
  if (moves.isEmpty) return const [];

  final useReport = game.hasReportClassifications;
  final scores = <EngineScore?>[
    for (final move in moves)
      EngineScore.fromLine(centipawns: move.cp, mate: move.mate),
  ];
  final startScore = game.headers['FEN'] == null ? _initialPositionScore : null;

  final candidates = List<_Candidate?>.filled(moves.length, null);
  for (var i = 0; i < moves.length; i++) {
    final move = moves[i];
    final previous = i == 0 ? startScore : scores[i - 1];
    candidates[i] =
        _checkmate(move, isLast: i == moves.length - 1) ??
        _judgement(move, useReport, previous, scores[i]) ??
        _sacrifice(game, i, previous, scores) ??
        _promotion(move) ??
        _check(move) ??
        _capture(moves, i) ??
        _castle(move);
  }

  _capHeadlines(candidates, maxHeadlines);
  _markGameEnd(candidates, game);
  return [for (final candidate in candidates) candidate?.toMoment()];
}

// ---------------------------------------------------------------------------
// Candidates
// ---------------------------------------------------------------------------

class _Candidate {
  const _Candidate(this.type, this.label, this.severity, {this.weight = 0});

  final FeedMomentType type;
  final String label;
  final int severity;

  /// Tie-breaker when more headlines compete than [kFlowMaxHeadlines] allows:
  /// winning chances thrown away, or pawns sacrificed.
  final double weight;

  /// Which headlines survive the cap first. Mate always does; a brilliancy or
  /// a sacrifice outranks a blunder because Feed is a highlight reel.
  int get headlineRank => switch (type) {
    FeedMomentType.checkmate => 0,
    FeedMomentType.brilliant => 1,
    FeedMomentType.sacrifice => 2,
    FeedMomentType.blunder => 3,
    _ => 9,
  };

  _Candidate demoted() => _Candidate(type, label, 2, weight: weight);

  FeedMoment toMoment() =>
      FeedMoment(type: type, label: label, severity: severity);
}

_Candidate? _checkmate(FeedPgnMove move, {required bool isLast}) {
  if (!isLast) return null;
  if (!move.san.contains('#') && !move.after.isCheckmate) return null;
  return const _Candidate(FeedMomentType.checkmate, 'Checkmate', 3, weight: 10);
}

_Candidate? _judgement(
  FeedPgnMove move,
  bool useReport,
  EngineScore? previous,
  EngineScore? current,
) {
  if (useReport) return _fromClassification(move.classification);
  return _fromGlyphNags(move.nags) ?? _fromEvalSwing(move, previous, current);
}

_Candidate? _fromClassification(GameMoveClassification? classification) =>
    switch (classification) {
      GameMoveClassification.brilliant => const _Candidate(
        FeedMomentType.brilliant,
        'Brilliant',
        3,
        weight: 1,
      ),
      GameMoveClassification.blunder => const _Candidate(
        FeedMomentType.blunder,
        'Blunder',
        3,
        weight: 1,
      ),
      GameMoveClassification.missedWin => const _Candidate(
        FeedMomentType.missedWin,
        'Missed win',
        2,
      ),
      GameMoveClassification.mistake => const _Candidate(
        FeedMomentType.mistake,
        'Mistake',
        2,
      ),
      GameMoveClassification.inaccuracy => const _Candidate(
        FeedMomentType.inaccuracy,
        'Inaccuracy',
        1,
      ),
      // Good, best and book moves are the game going to plan.
      _ => null,
    };

/// `$3` `!!`, `$4` `??`, `$2` `?`, `$6` `?!`.
_Candidate? _fromGlyphNags(List<int> nags) {
  if (nags.contains(3)) {
    return _fromClassification(GameMoveClassification.brilliant);
  }
  if (nags.contains(4)) {
    return _fromClassification(GameMoveClassification.blunder);
  }
  if (nags.contains(2)) {
    return _fromClassification(GameMoveClassification.mistake);
  }
  if (nags.contains(6)) {
    return _fromClassification(GameMoveClassification.inaccuracy);
  }
  return null;
}

_Candidate? _fromEvalSwing(
  FeedPgnMove move,
  EngineScore? previous,
  EngineScore? current,
) {
  if (previous == null || current == null) return null;
  final moverIsWhite = move.mover == Side.white;
  final judgement = lichessAdvice(
    previous: previous,
    current: current,
    moverIsWhite: moverIsWhite,
    engineBestUci: _unknownBestMove,
    playedUci: move.uci,
  );
  if (judgement == null) return null;

  final before = _moverWinningChances(previous, moverIsWhite: moverIsWhite);
  final after = _moverWinningChances(current, moverIsWhite: moverIsWhite);
  final swing = before - after;

  // Throwing away a won position without actually losing it is its own story:
  // ChessEver's report calls it a missed win, and so does Feed.
  if (judgement != LichessJudgement.inaccuracy &&
      before >= 0.5 &&
      after > -0.3) {
    return _Candidate(FeedMomentType.missedWin, 'Missed win', 2, weight: swing);
  }
  return switch (judgement) {
    LichessJudgement.blunder => _Candidate(
      FeedMomentType.blunder,
      'Blunder',
      3,
      weight: swing,
    ),
    LichessJudgement.mistake => _Candidate(
      FeedMomentType.mistake,
      'Mistake',
      2,
      weight: swing,
    ),
    LichessJudgement.inaccuracy => _Candidate(
      FeedMomentType.inaccuracy,
      'Inaccuracy',
      1,
      weight: swing,
    ),
  };
}

/// Mover-relative winning chances in `[-1, 1]`; a forced mate is ±1.
double _moverWinningChances(EngineScore score, {required bool moverIsWhite}) {
  final pov = score.invertIf(!moverIsWhite);
  return switch (pov) {
    CpScore(:final centipawns) => lichessWinningChances(centipawns),
    MateScore(:final moves) => moves > 0 ? 1.0 : -1.0,
  };
}

/// A move that hands over at least [kFlowSacrificeMinMaterial] pawns of
/// material which is *not* won straight back.
///
/// Read off the game as played, not a search: the opponent's reply must
/// capture a unit worth ≥ 3 that this move put en prise (it moved there, or it
/// was not attacked before this move — a discovered hang like Legall's queen),
/// and after the mover's next move the net material is still down ≥ 3. A
/// temporary sacrifice that regains material later still counts; an exchange
/// that is simply completed does not.
///
/// A blunder satisfies all of that too, so the mover must also not end worse:
/// no error verdict (report or glyph), no eval loss by the lichess table when
/// evals exist, and — with no evals — the mover went on to win (or drew with a
/// check, the perpetual-after-a-sacrifice case).
_Candidate? _sacrifice(
  FeedPgnGame game,
  int index,
  EngineScore? previous,
  List<EngineScore?> scores,
) {
  final moves = game.moves;
  if (index + 1 >= moves.length) return null;
  final move = moves[index];
  // A forced evasion that loses material is a loss, not a choice.
  if (move.before.isCheck) return null;

  final mover = move.mover;
  final opponent = mover.opposite;
  final reply = moves[index + 1];
  final replyMove = reply.move;
  if (replyMove is! NormalMove) return null;

  final target = replyMove.to;
  final victim = reply.before.board.pieceAt(target);
  if (victim == null || victim.color != mover || victim.role == Role.king) {
    return null;
  }
  final victimValue = reportPieceValue(victim.role);
  if (victimValue < kFlowSacrificeMinMaterial) return null;

  final played = move.move;
  final movedTo = played is NormalMove ? played.to : null;
  final offered =
      target == movedTo || !isSquareAttackedBy(move.before, target, opponent);
  if (!offered) return null;

  final sign = mover == Side.white ? 1 : -1;
  final materialBefore = reportMaterialBalanceWhite(move.before) * sign;
  final settled = index + 2 < moves.length
      ? moves[index + 2].after
      : reply.after;
  final materialAfter = reportMaterialBalanceWhite(settled) * sign;
  final given = materialBefore - materialAfter;
  if (given < kFlowSacrificeMinMaterial) return null;

  if (!_sacrificeHolds(game, index, previous, scores[index])) return null;

  final label = switch (victim.role) {
    Role.queen => 'Queen sacrifice',
    Role.rook => 'Rook sacrifice',
    _ => 'Piece sacrifice',
  };
  return _Candidate(
    FeedMomentType.sacrifice,
    label,
    3,
    weight: given.toDouble(),
  );
}

bool _sacrificeHolds(
  FeedPgnGame game,
  int index,
  EngineScore? previous,
  EngineScore? current,
) {
  final move = game.moves[index];
  switch (move.classification) {
    case GameMoveClassification.inaccuracy:
    case GameMoveClassification.mistake:
    case GameMoveClassification.blunder:
    case GameMoveClassification.missedWin:
      return false;
    case GameMoveClassification.brilliant:
      return true;
    default:
      break;
  }
  if (move.nags.any((nag) => nag == 2 || nag == 4 || nag == 6)) return false;

  if (previous != null && current != null) {
    return lichessAdvice(
          previous: previous,
          current: current,
          moverIsWhite: move.mover == Side.white,
          engineBestUci: _unknownBestMove,
          playedUci: move.uci,
        ) ==
        null;
  }
  if (move.nags.contains(1) || move.nags.contains(3)) return true;

  final winner = game.winner;
  if (winner != null) return winner == move.mover;
  if (game.result == '½-½') {
    final moves = game.moves;
    return move.after.isCheck ||
        (index + 2 < moves.length && moves[index + 2].after.isCheck);
  }
  return false;
}

_Candidate? _promotion(FeedPgnMove move) {
  final played = move.move;
  if (played is! NormalMove || played.promotion == null) return null;
  final isQueen = played.promotion == Role.queen;
  return _Candidate(
    FeedMomentType.promotion,
    isQueen ? 'Promotion' : 'Underpromotion',
    2,
    weight: isQueen ? 0 : 1,
  );
}

_Candidate? _check(FeedPgnMove move) {
  if (!move.san.contains('+')) return null;
  return const _Candidate(FeedMomentType.check, 'Check', 1);
}

/// Captures, weighted by what they win: taking a queen or rook for less, or
/// any undefended piece, is a severity-2 beat; trades and pawn grabs are 1.
_Candidate? _capture(List<FeedPgnMove> moves, int index) {
  final move = moves[index];
  if (!move.san.contains('x')) return null;
  final facts = describeMove(
    beforeFen: move.before.fen,
    playedUci: move.uci,
    previousUci: index > 0 ? moves[index - 1].uci : null,
  );
  if (facts.isForcedRecapture) {
    return const _Candidate(FeedMomentType.capture, 'Recapture', 1);
  }
  // En passant leaves the target square empty: a pawn either way.
  final value = facts.captureValue > 0 ? facts.captureValue : 1;
  final winsMaterial =
      facts.capturedPieceWasLoose || facts.movedPieceValue < value;
  if (value >= 3 && winsMaterial) {
    final label = switch (value) {
      >= 9 => 'Wins the queen',
      >= 5 => 'Wins a rook',
      _ => 'Wins a piece',
    };
    return _Candidate(
      FeedMomentType.capture,
      label,
      2,
      weight: value.toDouble(),
    );
  }
  return const _Candidate(FeedMomentType.capture, 'Capture', 1);
}

_Candidate? _castle(FeedPgnMove move) {
  if (!move.san.startsWith('O-O')) return null;
  return _Candidate(
    FeedMomentType.castle,
    move.san.startsWith('O-O-O') ? 'Castles long' : 'Castles',
    1,
  );
}

/// Keeps the [maxHeadlines] strongest severity-3 moments and demotes the rest
/// to severity 2, so they still caption and sound but playback does not stop.
void _capHeadlines(List<_Candidate?> candidates, int maxHeadlines) {
  final headlines = <int>[
    for (var i = 0; i < candidates.length; i++)
      if ((candidates[i]?.severity ?? 0) >= 3) i,
  ];
  if (headlines.length <= maxHeadlines) return;
  headlines.sort((a, b) {
    final left = candidates[a]!;
    final right = candidates[b]!;
    final byRank = left.headlineRank.compareTo(right.headlineRank);
    if (byRank != 0) return byRank;
    final byWeight = right.weight.compareTo(left.weight);
    if (byWeight != 0) return byWeight;
    // Later moments decide games; prefer them.
    return b.compareTo(a);
  });
  for (final index in headlines.skip(maxHeadlines)) {
    candidates[index] = candidates[index]!.demoted();
  }
}

/// The final ply carries the result, unless it is already a headline (mate, a
/// brilliancy, a sacrifice or the losing blunder), which says more.
void _markGameEnd(List<_Candidate?> candidates, FeedPgnGame game) {
  final result = game.result;
  if (result == null || candidates.isEmpty) return;
  final last = candidates.length - 1;
  if ((candidates[last]?.severity ?? 0) >= 3) return;
  candidates[last] = _Candidate(FeedMomentType.gameEnd, switch (result) {
    '1-0' => 'White wins',
    '0-1' => 'Black wins',
    _ => 'Draw',
  }, 2);
}
