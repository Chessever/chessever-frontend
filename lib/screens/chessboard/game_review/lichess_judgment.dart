import 'dart:math' as math;

/// Lichess's move judgment, ported rule for rule.
///
/// `?!`, `?` and `??` in Game Review come from this file and nowhere else, so a
/// move earns the same symbol here that the same position earns on lichess.org.
/// Anything that wants to soften, upgrade or suppress an error has to be
/// written as an explicit overlay at the call site — never by retuning what is
/// below, which is a transcription and not a design.
///
/// Sources (lichess-org, read 2026-07-26):
/// - `lila/modules/tree/src/main/Advice.scala` — `CpAdvice`, `MateAdvice`,
///   `MateSequence`, and the `.3 / .2 / .1` judgment table.
/// - `lila/modules/tree/src/main/Analysis.scala` — `infoAdvices`, home of the
///   `hasVariation` gate: a move the engine itself would have played is never
///   judged, however the evaluation moved.
/// - `lila/modules/fishnet/src/main/AnalysisBuilder.scala` — `makeInfos`, which
///   defines that variation (the engine's line at the position before the move,
///   kept only when its first move is not the move played) and normalises every
///   score to White.
/// - `scalachess/core/src/main/scala/eval.scala` — `WinPercent.winningChances`
///   and the `Score` / `Cp` / `Mate` shapes modelled by [EngineScore].
///
/// One deliberate deviation, at the caller: lichess measures the first move of a
/// game against a fixed +0.15 (`Info.start` / `evals.initial`) because fishnet
/// never evaluates the starting position. We do evaluate it, so we use that real
/// score. It can only change a verdict on move one.
enum LichessJudgement {
  inaccuracy('?!'),
  mistake('?'),
  blunder('??');

  const LichessJudgement(this.glyph);

  /// The PGN suffix lichess attaches (`Glyph.MoveAssessment.dubious` /
  /// `.mistake` / `.blunder`).
  final String glyph;
}

/// A Stockfish score for one position: centipawns **or** a mate distance, never
/// both — `chess.eval.Score`.
///
/// Values are White's point of view, matching both `AnalysisBuilder.makeInfos`
/// and the engine layer here (`normalizeStockfishPvsToWhitePerspective`).
sealed class EngineScore {
  const EngineScore();

  /// `Eval.score`: `cp.map(Cp).orElse(mate.map(Mate))` — centipawns win when a
  /// line somehow carries both, and a line carrying neither has no score.
  static EngineScore? fromLine({int? centipawns, int? mate}) {
    if (centipawns != null) return CpScore(centipawns);
    if (mate != null) return MateScore(mate);
    return null;
  }

  EngineScore get inverted;

  /// `Score.invertIf` — used to turn a White-relative score into the mover's.
  EngineScore invertIf(bool condition) => condition ? inverted : this;

  /// `prevPovScore.cp.so(_.centipawns)`: a mate score contributes zero, which is
  /// what makes the `> 999` / `< -700` tests in [_mateAdvice] fall through to
  /// Blunder when both ends are mates.
  int get centipawnsOrZero;
}

final class CpScore extends EngineScore {
  const CpScore(this.centipawns);

  final int centipawns;

  @override
  EngineScore get inverted => CpScore(-centipawns);

  @override
  int get centipawnsOrZero => centipawns;
}

final class MateScore extends EngineScore {
  const MateScore(this.moves);

  /// Positive = White delivers the mate.
  final int moves;

  /// `Mate.positive` / `Mate.negative`. Mate in zero is neither: it is a
  /// finished game, and lichess drops those evaluations before judging at all.
  bool get isPositive => moves > 0;
  bool get isNegative => moves < 0;

  @override
  EngineScore get inverted => MateScore(-moves);

  @override
  int get centipawnsOrZero => 0;
}

/// `WinPercent.winningChances`: how likely the position is to be won, in
/// `[-1, +1]`, where `+1` is winning for White.
///
/// The multiplier is lichess's own (lila PR #11148). Note the clamp is on the
/// *result*, not on the centipawns: lila's advice path calls `winningChances`
/// directly and never ceils the score to ±1000, so +25.00 really does sit nearer
/// to +1 here than +10.00 does. Do not "fix" this by clamping the input — that
/// is a different function, and it would move the thresholds below.
double lichessWinningChances(int centipawns) {
  const multiplier = -0.00368208;
  return (2 / (1 + math.exp(multiplier * centipawns)) - 1).clamp(-1.0, 1.0);
}

/// `CpAdvice.winningChanceJudgements`, in lila's order: the first row whose
/// threshold the mover's loss reaches is the verdict.
///
/// The units are winning chances, so these read as 30 / 20 / 10 points of a
/// `[-1, +1]` scale — half that in the `0…100` win-percentage the eval graph
/// shows (15 / 10 / 5 points). Comparing against the graph's numbers instead is
/// exactly how a blunder threshold drifts.
const List<(double, LichessJudgement)> _winningChanceJudgements = [
  (0.3, LichessJudgement.blunder),
  (0.2, LichessJudgement.mistake),
  (0.1, LichessJudgement.inaccuracy),
];

/// `Advice.apply`, plus the `hasVariation` gate that decides whether lichess
/// asks for a judgment in the first place.
///
/// [previous] is the score of the position the mover faced, [current] the score
/// after the move, both White-relative. [engineBestUci] is the first move of the
/// engine's line at that earlier position, or null when the search returned no
/// line at all.
LichessJudgement? lichessAdvice({
  required EngineScore? previous,
  required EngineScore? current,
  required bool moverIsWhite,
  required String? engineBestUci,
  required String playedUci,
}) {
  // `infoAdvices`: `info.hasVariation.so(Advice(prev, info))`, where the
  // variation is the engine's line kept only when it starts with a *different*
  // move (`makeInfos`). So the engine's own choice is never an error — if there
  // was nothing better to play, there was nothing to punish — and a position the
  // engine gave no line for is never judged either.
  if (engineBestUci == null || engineBestUci == playedUci) return null;
  if (previous == null || current == null) return null;
  return _cpAdvice(previous, current, moverIsWhite: moverIsWhite) ??
      _mateAdvice(previous, current, moverIsWhite: moverIsWhite);
}

/// `CpAdvice`: winning chances the mover handed over, judged on the table above.
LichessJudgement? _cpAdvice(
  EngineScore previous,
  EngineScore current, {
  required bool moverIsWhite,
}) {
  // `for cp <- prev.cp; infoCp <- info.cp` — a mate at either end has no
  // centipawns, so it drops through to [_mateAdvice].
  if (previous is! CpScore || current is! CpScore) return null;
  final change =
      lichessWinningChances(current.centipawns) -
      lichessWinningChances(previous.centipawns);
  // `info.color.fold(-d, d)`: a positive delta is winning chances *lost* by
  // whoever moved.
  final delta = moverIsWhite ? -change : change;
  for (final (threshold, judgement) in _winningChanceJudgements) {
    if (threshold <= delta) return judgement;
  }
  return null;
}

/// `MateSequence`: the only mate transitions lichess treats as damage.
enum _MateSequence {
  /// "Checkmate is now unavoidable" — the mover was on centipawns and is now
  /// being mated.
  created,

  /// "Lost forced checkmate sequence" — the mover had a forced mate and gave it
  /// up, either back to centipawns or into being mated itself.
  lost,

  /// "Not the best checkmate sequence". lila still carries this case and judges
  /// nothing for it; `MateSequence.apply` cannot actually produce it, so mating
  /// a move later than necessary is silent. Kept so this file reads against the
  /// Scala.
  delayed;

  /// Mover-relative, so `positive` means the mover is the one mating.
  static _MateSequence? of(EngineScore previous, EngineScore current) {
    if (previous is CpScore && current is MateScore && current.isNegative) {
      return created;
    }
    if (previous is MateScore && previous.isPositive) {
      if (current is CpScore) return lost;
      if (current is MateScore && current.isNegative) return lost;
    }
    // Everything else is silence: mate held (or shortened) in either direction,
    // a mate escaped, a mate delivered.
    return null;
  }
}

/// `MateAdvice`: severity comes from how decided the position already was, so
/// walking into a mate from a lost game, or losing a mate while still crushing,
/// is only an Inaccuracy.
LichessJudgement? _mateAdvice(
  EngineScore previous,
  EngineScore current, {
  required bool moverIsWhite,
}) {
  final previousPov = previous.invertIf(!moverIsWhite);
  final currentPov = current.invertIf(!moverIsWhite);
  final sequence = _MateSequence.of(previousPov, currentPov);
  if (sequence == null) return null;
  final previousCp = previousPov.centipawnsOrZero;
  final currentCp = currentPov.centipawnsOrZero;
  return switch (sequence) {
    _MateSequence.created =>
      previousCp < -999
          ? LichessJudgement.inaccuracy
          : previousCp < -700
          ? LichessJudgement.mistake
          : LichessJudgement.blunder,
    _MateSequence.lost =>
      currentCp > 999
          ? LichessJudgement.inaccuracy
          : currentCp > 700
          ? LichessJudgement.mistake
          : LichessJudgement.blunder,
    _MateSequence.delayed => null,
  };
}
