import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart'
    show GameMoveClassification;
import 'package:chessever2/screens/chessboard/utils/pgn_comment_annotations.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart'
    show NagCategory, getNagDisplay, nagShownAsText;
import 'package:chessever2/screens/feed/logic/feed_moments.dart'
    show detectFlowMoments;
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart'
    show FeedMoment, FeedMomentType;
import 'package:chessground/chessground.dart' show Shape;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// A game story shows at most this many positions.
const int kStoryMaxSegments = 4;

/// At most this many of a collection game's positions ask the reader for a
/// move: the story stays a story, never a run of puzzles. A Missed chances
/// story asks on every position it has an answer for.
const int kStoryMaxPuzzles = 2;

/// How a segment's label reads: a strong move, a bad one, or neither.
enum StoryTone { strong, weak, neutral }

/// What the reader is asked on a segment that waits for a move.
enum StoryPuzzleKind {
  /// A strong move was played here: find it.
  findPlayed,

  /// A winning move was there and the player missed it: find the win.
  findMissed,
}

/// A position the reader is asked to solve: the side to move, the move that
/// answers it, and for a missed win the move that was actually played.
@immutable
class StoryPuzzle {
  const StoryPuzzle({
    required this.kind,
    required this.solver,
    required this.answer,
    required this.answerSan,
    required this.answerFen,
    this.line,
    this.ask = 'Find the strongest move.',
    this.hint,
  });

  final StoryPuzzleKind kind;

  /// Who is to move in the position asked.
  final Side solver;

  /// The move that solves it.
  final Move answer;
  final String answerSan;

  /// The position after [answer].
  final String answerFen;

  /// A missed win's line as the PGN gives it (`61. Nxa5 Re8 62. Kc5`).
  final String? line;

  /// What to look for ("Find the sacrifice.").
  final String ask;

  /// A word on the position while it asks, never the answer: what the
  /// evaluation said ("There is mate in one.").
  final String? hint;

  String get sideName => solver == Side.white ? 'White' : 'Black';

  /// The prompt's two lines: who is to move, and what to look for.
  (String, String) get prompt => switch (kind) {
    StoryPuzzleKind.findPlayed => ('$sideName to move', ask),
    StoryPuzzleKind.findMissed => ('$sideName missed a win here', ask),
  };
}

/// One key position of a game story, readable at a glance: the board after
/// a move that matters, the move, why it matters, and the book's words.
@immutable
class StorySegment {
  const StorySegment({
    required this.ply,
    required this.fenBefore,
    required this.fenAfter,
    required this.move,
    required this.san,
    required this.moveNumber,
    required this.white,
    this.moveBefore,
    this.nags = const [],
    this.label,
    this.tone = StoryTone.neutral,
    this.moveClass,
    this.comment,
    this.shapes = const {},
    this.puzzle,
    this.tier = 3,
    this.finalPly = false,
  });

  /// A board that does not move: [fen] with [lastMove] highlighted, and
  /// [label] under it (a game whose moves are not readable here).
  factory StorySegment.still(String? fen, Move? lastMove, {String? label}) {
    final position = fen == null || fen.trim().isEmpty
        ? Chess.initial.fen
        : fen;
    return StorySegment(
      ply: 0,
      fenBefore: position,
      fenAfter: position,
      move: lastMove,
      san: null,
      moveNumber: 0,
      white: true,
      label: label,
      finalPly: true,
    );
  }

  /// The move's place in the mainline, 1 for White's first move; 0 for a
  /// [StorySegment.still].
  final int ply;

  /// The position before the move (the one a puzzle asks from) and after.
  final String fenBefore;
  final String fenAfter;

  /// The move into [fenAfter], and the one into [fenBefore].
  final Move? move;
  final Move? moveBefore;

  /// The move as the notation prints it; null for a still.
  final String? san;
  final int moveNumber;

  /// White played [move].
  final bool white;

  /// The glyphs printed after the SAN (`!!`, `?`, `±`), quality first.
  final List<int> nags;

  /// Why the position matters, in a word or two ("Brilliant", "Blunder",
  /// "Missed win", "Queen sacrifice"); null when the book's words say it.
  final String? label;
  final StoryTone tone;

  /// The verdict's badge on the board, when the move carries one.
  final MoveClass? moveClass;

  /// The annotator's words (or, for a missed win, what the evaluation says).
  final String? comment;

  /// The move's arrows and marked squares.
  final Set<Shape> shapes;

  /// Set when the reader is asked to find a move here.
  final StoryPuzzle? puzzle;

  /// Why the position was picked: 0 the annotator's words or drawings,
  /// 1 a verdict on the move, 2 an evaluation swing, 3 what the board shows.
  final int tier;

  /// The game's last move: the game's result shows with it.
  final bool finalPly;

  bool get isStill => ply == 0;

  /// "23." for White's move, "23…" for Black's.
  String get number => white ? '$moveNumber.' : '$moveNumber…';

  /// The board's move index for this position, as the board screen counts
  /// (-1 is the start): after the move, or before it while a puzzle waits.
  int boardMoveIndex({required bool before}) =>
      math.max(-1, before ? ply - 2 : ply - 1);

  /// The words the reader reads on this segment, for its reading time.
  int get readLength => (label?.length ?? 0) + (comment?.length ?? 0);
}

/// How long [segment] stays: a base for the board, then the time to read
/// its words at about 18 characters a second, never more than [max].
Duration storySegmentDuration(StorySegment segment) {
  const base = 3.2;
  const perChar = 0.055;
  const max = 12.0;
  final seconds = math.min(max, base + perChar * segment.readLength);
  return Duration(milliseconds: (seconds * 1000).round());
}

// ---------------------------------------------------------------- parsing

/// A better move a PGN gives for a mainline move: the first move of the
/// first variation beside it (an annotator's improvement, a report's
/// engine line), with the line's first few moves in notation.
@immutable
class StoryAlternative {
  const StoryAlternative({
    required this.move,
    required this.san,
    required this.fenAfter,
    required this.line,
  });

  final Move move;
  final String san;
  final String fenAfter;
  final String line;
}

/// A game read for its stories: the mainline with what the moment finder
/// needs, and the variation beside each move.
@immutable
class StoryPgn {
  const StoryPgn({required this.game, required this.alternatives});

  final FeedPgnGame game;

  /// One per mainline move, null where the PGN gives no variation.
  final List<StoryAlternative?> alternatives;
}

/// Reads [pgn] for its stories; null when it holds no playable move.
StoryPgn? parseStoryPgn(String? pgn) {
  if (pgn == null || pgn.trim().isEmpty) return null;
  final game = parseFlowPgn(pgn);
  if (game == null) return null;
  final alternatives = List<StoryAlternative?>.filled(game.moves.length, null);
  try {
    final parsed = PgnGame.parsePgn(pgn.trim());
    PgnNode<PgnNodeData> node = parsed.moves;
    var i = 0;
    while (node.children.isNotEmpty && i < game.moves.length) {
      if (node.children.length > 1) {
        alternatives[i] = _alternative(node.children[1], game.moves[i].before);
      }
      node = node.children.first;
      i++;
    }
  } catch (_) {
    // A damaged variation never costs the mainline.
  }
  return StoryPgn(game: game, alternatives: List.unmodifiable(alternatives));
}

StoryAlternative? _alternative(PgnChildNode<PgnNodeData> start, Position at) {
  var position = at;
  PgnChildNode<PgnNodeData>? node = start;
  Move? first;
  String? firstSan;
  String? firstFen;
  final words = <String>[];
  var plies = 0;
  while (node != null && plies < 4) {
    final Move? move;
    try {
      move = position.parseSan(node.data.san);
    } catch (_) {
      break;
    }
    if (move == null) break;
    final white = position.turn == Side.white;
    final number = position.fullmoves;
    final (next, san) = position.makeSan(move);
    if (white) {
      words.add('$number. $san');
    } else {
      words.add(plies == 0 ? '$number… $san' : san);
    }
    if (first == null) {
      first = move;
      firstSan = san;
      firstFen = next.fen;
    }
    position = next;
    plies++;
    node = node.children.isEmpty ? null : node.children.first;
  }
  if (first == null) return null;
  return StoryAlternative(
    move: first,
    san: firstSan!,
    fenAfter: firstFen!,
    line: words.join(' '),
  );
}

// ---------------------------------------------------------------- verdicts

/// A verdict on a move: from a report's classification (which owns every
/// verdict when the game has one) or a glyph the annotator gave it.
@immutable
class _Verdict {
  const _Verdict(this.label, this.tone, this.moveClass, this.weight);

  final String label;
  final StoryTone tone;
  final MoveClass moveClass;
  final double weight;

  bool get strong => tone == StoryTone.strong;
}

const _brilliant = _Verdict(
  'Brilliant',
  StoryTone.strong,
  MoveClass.brilliant,
  1.0,
);
const _great = _Verdict('Great move', StoryTone.strong, MoveClass.great, 0.7);
const _strong = _Verdict(
  'Strong move',
  StoryTone.strong,
  MoveClass.great,
  0.65,
);
const _only = _Verdict('Only move', StoryTone.strong, MoveClass.great, 0.6);
const _missedWin = _Verdict(
  'Missed win',
  StoryTone.weak,
  MoveClass.missedWin,
  0.9,
);
const _blunder = _Verdict('Blunder', StoryTone.weak, MoveClass.blunder, 0.85);
const _mistake = _Verdict('Mistake', StoryTone.weak, MoveClass.mistake, 0.6);

/// Glyph verdicts that only ever lift a commented move, never pick one.
const _interesting = _Verdict(
  'Interesting',
  StoryTone.neutral,
  MoveClass.interesting,
  0.3,
);
const _dubious = _Verdict('Dubious', StoryTone.weak, MoveClass.inaccuracy, 0.3);
const _inaccuracy = _Verdict(
  'Inaccuracy',
  StoryTone.weak,
  MoveClass.inaccuracy,
  0.2,
);

_Verdict? _verdictOf(FeedPgnMove move, {required bool report}) {
  if (report) {
    return switch (move.classification) {
      GameMoveClassification.brilliant => _brilliant,
      GameMoveClassification.goodMove => _great,
      GameMoveClassification.missedWin => _missedWin,
      GameMoveClassification.blunder => _blunder,
      GameMoveClassification.mistake => _mistake,
      GameMoveClassification.inaccuracy => _inaccuracy,
      _ => null,
    };
  }
  final nags = move.nags;
  if (nags.contains(3)) return _brilliant;
  if (nags.contains(4)) return _blunder;
  if (nags.contains(1)) return _strong;
  if (nags.contains(7)) return _only;
  if (nags.contains(2)) return _mistake;
  if (nags.contains(5)) return _interesting;
  if (nags.contains(6)) return _dubious;
  return null;
}

/// A verdict that picks a position on its own (tier 1).
bool _picks(_Verdict verdict) =>
    verdict != _interesting && verdict != _dubious && verdict != _inaccuracy;

/// The glyphs printed after a move's SAN: printable ones, quality first.
List<int> _printedNags(FeedPgnMove move) {
  final glyphs = [
    for (final nag in move.nags)
      if (nagShownAsText(nag) && getNagDisplay(nag) != null) nag,
  ];
  final quality = [
    for (final nag in glyphs)
      if (getNagDisplay(nag)!.category == NagCategory.quality) nag,
  ];
  return List.unmodifiable({...quality, ...glyphs});
}

// ----------------------------------------------------------------- picking

class _Candidate {
  _Candidate({
    required this.index,
    required this.tier,
    required this.weight,
    this.verdict,
    this.moment,
    this.comment,
    this.shapes = const [],
  });

  final int index;
  final int tier;
  final double weight;
  final _Verdict? verdict;
  final FeedMoment? moment;
  final String? comment;
  final List<Shape> shapes;
}

/// What the board shows that is worth a story on its own: mate, a
/// sacrifice, material won, a promotion. Checks, castling and plain trades
/// never are.
bool _boardWorthy(FeedMoment? moment) => switch (moment?.type) {
  FeedMomentType.sacrifice ||
  FeedMomentType.promotion ||
  FeedMomentType.checkmate => true,
  FeedMomentType.capture => (moment?.severity ?? 0) >= 2,
  _ => false,
};

/// The eval-swing verdicts the moment finder makes when no one judged the
/// move (no report, no glyph).
_Verdict? _swingVerdict(FeedMoment? moment) => switch (moment?.type) {
  FeedMomentType.missedWin => _missedWin,
  FeedMomentType.blunder => _blunder,
  FeedMomentType.mistake => _mistake,
  _ => null,
};

/// Up to [max] key positions of [story], with no engine:
///
/// 1. moves the annotator spoke to or drew on (their words, arrows);
/// 2. moves with a verdict: a report's classification, or a glyph
///    (`!!`, `!`, `??`, `?`), and mate;
/// 3. evaluation swings in the PGN's `[%eval]`, judged as lichess judges;
/// 4. what the board shows: a sacrifice, material won, a promotion.
///
/// The strongest evidence picks first, then the heavier moment, spread
/// over the game (never two within a few moves of each other while another
/// moment is free). Returned in game order. Empty when nothing in the game
/// is worth a stop.
///
/// A strong move that was played, or a missed win whose winning move the
/// PGN gives (a variation beside it), asks the reader for the move, on at
/// most [maxPuzzles] of the positions picked.
List<StorySegment> pickStorySegments(
  StoryPgn story, {
  int max = kStoryMaxSegments,
  int maxPuzzles = kStoryMaxPuzzles,
}) {
  final game = story.game;
  final moves = game.moves;
  if (moves.isEmpty || max <= 0) return const [];
  final report = game.hasReportClassifications;
  final moments = detectFlowMoments(game);
  final candidates = <_Candidate>[];
  for (var i = 0; i < moves.length; i++) {
    final move = moves[i];
    final comment = pgnCommentProse(move.comments);
    final shapes = pgnCommentShapes(move.comments);
    final verdict = _verdictOf(move, report: report);
    final moment = i < moments.length ? moments[i] : null;
    final swing = verdict == null ? _swingVerdict(moment) : null;
    if (comment != null || shapes.isNotEmpty) {
      candidates.add(
        _Candidate(
          index: i,
          tier: 0,
          weight:
              math.min(comment?.length ?? 0, 240) / 240 +
              (verdict != null ? 0.6 : 0) +
              (shapes.isNotEmpty ? 0.3 : 0),
          verdict: verdict ?? swing,
          moment: moment,
          comment: comment,
          shapes: shapes,
        ),
      );
    } else if (verdict != null && _picks(verdict)) {
      candidates.add(
        _Candidate(
          index: i,
          tier: 1,
          weight: verdict.weight,
          verdict: verdict,
          moment: moment,
        ),
      );
    } else if (moment?.type == FeedMomentType.checkmate) {
      candidates.add(
        _Candidate(index: i, tier: 1, weight: 0.95, moment: moment),
      );
    } else if (swing != null) {
      candidates.add(
        _Candidate(
          index: i,
          tier: 2,
          weight: swing.weight,
          verdict: swing,
          moment: moment,
        ),
      );
    } else if (_boardWorthy(moment)) {
      candidates.add(
        _Candidate(
          index: i,
          tier: 3,
          weight: switch (moment!.type) {
            FeedMomentType.sacrifice => 0.9,
            FeedMomentType.promotion => 0.3,
            _ => 0.5,
          },
          verdict: verdict,
          moment: moment,
        ),
      );
    }
  }
  final picked = _spread(candidates, moves.length, max);
  // Puzzles on the strongest moves that can ask one: a brilliancy before
  // a good move, then the heavier position.
  final asks = <int>{};
  double strength(_Candidate c) =>
      c.verdict?.weight ??
      (c.moment?.type == FeedMomentType.sacrifice ? 0.9 : 0.5);
  final byStrength = [...picked]
    ..sort((a, b) {
      final byVerdict = strength(b).compareTo(strength(a));
      return byVerdict != 0 ? byVerdict : _strongestFirst(a, b);
    });
  for (final c in byStrength) {
    if (asks.length >= maxPuzzles) break;
    if (_puzzleOf(story, c) != null) asks.add(c.index);
  }
  return [
    for (final c in picked)
      _segmentOf(story, c, puzzle: asks.contains(c.index)),
  ];
}

int _strongestFirst(_Candidate a, _Candidate b) {
  final byTier = a.tier.compareTo(b.tier);
  if (byTier != 0) return byTier;
  final byWeight = b.weight.compareTo(a.weight);
  if (byWeight != 0) return byWeight;
  // Later moments decide games.
  return b.index.compareTo(a.index);
}

/// The strongest of [candidates], at most [max], spread over a game of
/// [plies]: first never two within a few moves of each other, then (while
/// room is left) any distinct ones. In game order.
List<_Candidate> _spread(List<_Candidate> candidates, int plies, int max) {
  final sorted = [...candidates]..sort(_strongestFirst);
  final gap = math.max(3, (plies / (max * 2)).round());
  final picked = <_Candidate>[];
  for (final distance in [gap, 1]) {
    for (final c in sorted) {
      if (picked.length >= max) break;
      if (picked.contains(c)) continue;
      if (picked.any((p) => (p.index - c.index).abs() < distance)) continue;
      picked.add(c);
    }
  }
  picked.sort((a, b) => a.index.compareTo(b.index));
  return picked;
}

StoryPuzzle? _puzzleOf(StoryPgn story, _Candidate c) {
  final move = story.game.moves[c.index];
  final verdict = c.verdict;
  final solver = move.mover;
  // A forced reply is no question to ask.
  if (move.before.legalMoves.values.fold<int>(0, (n, s) => n + s.size) < 2) {
    return null;
  }
  final strong =
      (verdict != null && verdict.strong) ||
      (c.moment?.type == FeedMomentType.sacrifice &&
          (c.moment?.severity ?? 0) >= 3);
  if (strong) {
    final ask = switch (c.moment?.type) {
      FeedMomentType.sacrifice when verdict == null || verdict != _brilliant =>
        'Find the sacrifice.',
      FeedMomentType.checkmate => 'Find the mate.',
      _ =>
        verdict == _brilliant
            ? 'Find the brilliant move.'
            : 'Find the strongest move.',
    };
    return StoryPuzzle(
      kind: StoryPuzzleKind.findPlayed,
      solver: solver,
      answer: move.move,
      answerSan: move.san,
      answerFen: move.after.fen,
      ask: ask,
    );
  }
  if (verdict == _missedWin) {
    final alternative = story.alternatives[c.index];
    if (alternative == null) return null;
    final moves = story.game.moves;
    return StoryPuzzle(
      kind: StoryPuzzleKind.findMissed,
      solver: solver,
      answer: alternative.move,
      answerSan: alternative.san,
      answerFen: alternative.fenAfter,
      line: alternative.line,
      ask: 'Find it.',
      hint: c.index > 0 && moves[c.index - 1].hasEval
          ? _winningHint(moves[c.index - 1], solver)
          : null,
    );
  }
  return null;
}

/// What the evaluation before a missed win tells the solver, without the
/// move: a mate count, or how far ahead they stood.
String? _winningHint(FeedPgnMove before, Side solver) {
  final sign = solver == Side.white ? 1 : -1;
  final mate = before.mate;
  if (mate != null) {
    if (mate * sign <= 0) return null;
    final n = mate.abs();
    return n == 1 ? 'There is mate in one.' : 'There is a forced mate in $n.';
  }
  final cp = (before.cp ?? 0) * sign;
  if (cp < 150) return null;
  final side = solver == Side.white ? 'White' : 'Black';
  return '$side is winning here (${_evalText(before)}).';
}

StorySegment _segmentOf(StoryPgn story, _Candidate c, {required bool puzzle}) {
  final moves = story.game.moves;
  final move = moves[c.index];
  final verdict = c.verdict;
  final moment = c.moment;
  final heuristic = moment != null && _boardWorthy(moment)
      ? moment.label
      : null;
  final label =
      verdict?.label ??
      (moment?.type == FeedMomentType.checkmate ? 'Checkmate' : heuristic);
  final tone =
      verdict?.tone ??
      (moment?.type == FeedMomentType.sacrifice ||
              moment?.type == FeedMomentType.checkmate
          ? StoryTone.strong
          : StoryTone.neutral);
  return StorySegment(
    ply: move.ply,
    fenBefore: move.before.fen,
    fenAfter: move.after.fen,
    move: move.move,
    moveBefore: c.index > 0 ? moves[c.index - 1].move : null,
    san: move.san,
    moveNumber: move.before.fullmoves,
    white: move.mover == Side.white,
    nags: _printedNags(move),
    label: label,
    tone: tone,
    moveClass: verdict?.moveClass ?? move.moveClass,
    comment: c.comment ?? _evalNote(story, c.index, verdict),
    shapes: Set.unmodifiable(c.shapes),
    puzzle: puzzle ? _puzzleOf(story, c) : null,
    tier: c.tier,
    finalPly: c.index == moves.length - 1,
  );
}

// ------------------------------------------------------------ evaluations

/// A missed win or a blunder in words, from the evaluations the PGN
/// carries: how the game stood before the move, and after it ("It was
/// level (0.0). After Nf6, White mates in 1.").
String? _evalNote(StoryPgn story, int index, _Verdict? verdict) {
  if (verdict != _missedWin && verdict != _blunder) return null;
  final moves = story.game.moves;
  final move = moves[index];
  if (index == 0 || !moves[index - 1].hasEval || !move.hasEval) return null;
  return '${_stoodBefore(moves[index - 1])}. '
      'After ${move.san}, ${_standsAfter(move)}.';
}

/// How the game stood after [move], as a sentence's start: "White had mate
/// in 2", "It was level (0.2)", "Black was winning (−3.1)".
String _stoodBefore(FeedPgnMove move) {
  final mate = move.mate;
  if (mate != null) {
    return mate > 0 ? 'White had mate in $mate' : 'Black had mate in ${-mate}';
  }
  final cp = move.cp ?? 0;
  if (cp.abs() < 50) return 'It was level (${_evalText(move)})';
  final side = cp > 0 ? 'White' : 'Black';
  final word = cp.abs() >= 300 ? 'winning' : 'better';
  return '$side was $word (${_evalText(move)})';
}

/// How the game stands after [move], to end a sentence: "White mates in 1",
/// "it is level (+0.1)", "Black is winning (−3.1)".
String _standsAfter(FeedPgnMove move) {
  final mate = move.mate;
  if (mate != null) {
    return mate > 0 ? 'White mates in $mate' : 'Black mates in ${-mate}';
  }
  final cp = move.cp ?? 0;
  if (cp.abs() < 50) return 'it is level (${_evalText(move)})';
  final side = cp > 0 ? 'White' : 'Black';
  final word = cp.abs() >= 300 ? 'winning' : 'better';
  return '$side is $word (${_evalText(move)})';
}

/// An evaluation as the board's gauge prints it, from White's side: +1.4,
/// −0.3, 0.0, or a mate count.
String _evalText(FeedPgnMove move) {
  final mate = move.mate;
  if (mate != null) return mate > 0 ? 'mate in $mate' : 'mate in ${-mate}';
  final cp = move.cp ?? 0;
  if (cp == 0) return '0.0';
  final pawns = (cp.abs() / 100).toStringAsFixed(1);
  return cp > 0 ? '+$pawns' : '−$pawns';
}

/// Missed chances in [story]: the moves where the side that did not win
/// let a winning position go (a report's Missed win, or an evaluation of +3
/// or more falling to +0.5 or less, the Missed Chance topic's own rule),
/// and [hint] (the topic's chosen ply) when given. Up to [max], spread,
/// each asking the reader for the win when the PGN gives it.
List<StorySegment> pickMissedChanceSegments(
  StoryPgn story, {
  int? hint,
  int max = kStoryMaxSegments,
}) {
  final game = story.game;
  final moves = game.moves;
  if (moves.isEmpty) return const [];
  final winner = game.winner;
  final candidates = <_Candidate>[];
  int? score(FeedPgnMove m) {
    if (m.mate != null) return m.mate! > 0 ? 100000 : -100000;
    return m.cp;
  }

  for (var i = 1; i < moves.length; i++) {
    final move = moves[i];
    final mover = move.mover;
    final reportMiss = move.classification == GameMoveClassification.missedWin;
    final sign = mover == Side.white ? 1 : -1;
    final before = score(moves[i - 1]);
    final after = score(move);
    final ruleMiss =
        mover != winner &&
        before != null &&
        after != null &&
        before * sign >= 300 &&
        after * sign <= 50;
    final hinted = hint != null && move.ply == hint;
    if (!reportMiss && !ruleMiss && !hinted) continue;
    final known = story.alternatives[i] != null;
    candidates.add(
      _Candidate(
        index: i,
        tier: known ? 0 : 1,
        weight: (hinted ? 0.5 : 0) + (reportMiss ? 0.3 : 0) + (known ? 0.2 : 0),
        verdict: _missedWin,
      ),
    );
  }
  final picked = _spread(candidates, moves.length, max);
  return [
    for (final c in picked)
      _segmentOf(story, c, puzzle: story.alternatives[c.index] != null),
  ];
}
