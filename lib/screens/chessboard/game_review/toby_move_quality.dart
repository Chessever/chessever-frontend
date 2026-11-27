part of 'game_analysis_report.dart';

/// Read-only phone adapter for Desktop's Toby grading rules. Outcomes are
/// White-relative. Grade only the rows being published but compare them with
/// every evaluated alternative, including ones not shown in the strip.
/// The response and its board FEN are checked by the caller before publication.
Map<String, GameMoveClassification> gradeTobyMoves({
  required TobyReading reading,
  required TobyRequest request,
  required Position position,
  required Iterable<String> visibleUcis,
}) {
  final before = reading.positionWdl;
  if (!reading.isFinal ||
      before == null ||
      reading.sideToMove != position.turn) {
    return const {};
  }
  final isWhite = position.turn == Side.white;
  double whiteScore(TobyWdl wdl) => (wdl.white + wdl.draw / 2) * 100;
  double moverScore(double white) => isWhite ? white : 100 - white;
  final beforeWin = whiteScore(before);
  final moverBefore = moverScore(beforeWin);
  final outcomes = reading.outcomes;
  final fen = position.fen;
  final start = request.startFen ?? kInitialFEN;
  final moves = request.moves;
  final previousUci = moves.isEmpty ? null : moves.last;
  final previousMove = previousUci == null ? null : Move.parse(previousUci);
  String? previousFen;
  var previousFenRead = false;
  String? previousPositionFen() {
    if (previousFenRead) return previousFen;
    previousFenRead = true;
    try {
      Position prior = Chess.fromSetup(Setup.parseFen(start));
      for (final uci in moves.take(moves.length - 1)) {
        final move = Move.parse(uci);
        if (move == null || !prior.isLegal(move)) return null;
        prior = prior.play(move);
      }
      return previousFen = prior.fen;
    } catch (_) {
      return null;
    }
  }

  // Two strongest outcomes suffice to find the best distinct alternative
  // for each visible candidate, while preserving Desktop tie order.
  ({String uci, double white, double mover})? top, second;
  for (final outcome in outcomes) {
    final white = whiteScore(outcome.wdl);
    final line = (uci: outcome.uci, white: white, mover: moverScore(white));
    if (top == null || line.mover > top.mover) {
      if (line.uci != top?.uci) second = top;
      top = line;
    } else if (line.uci != top.uci &&
        (second == null || line.mover > second.mover)) {
      second = line;
    }
  }
  if (top == null) return const {};

  final grades = <String, GameMoveClassification>{};
  for (final uci in visibleUcis) {
    final candidate = reading.candidate(uci);
    final wdl = candidate?.wdl;
    if (candidate == null || wdl == null) continue;
    final afterWin = whiteScore(wdl);
    final moverAfter = moverScore(afterWin);
    final playedIsBest = uci == top.uci;
    final alternative = playedIsBest ? second : top;
    var moverChange = moverAfter - moverBefore;
    if (alternative != null) {
      moverChange = math.min(moverChange, moverAfter - top.mover);
    }
    final played = Move.parse(uci);
    final simpleRecapture =
        alternative != null &&
        previousMove is NormalMove &&
        played is NormalMove &&
        previousMove.to == played.to &&
        switch (previousPositionFen()) {
          final previous? => isSimpleReportRecapture(
            previous,
            previousUci!,
            uci,
          ),
          null => false,
        };
    final grade = _classifyTobyMove((
      beforeFen: fen,
      uci: uci,
      san: candidate.san,
      isWhite: isWhite,
      beforeWin: beforeWin,
      afterWin: afterWin,
      moverChange: moverChange,
      playedIsBest: playedIsBest,
      lineCount: outcomes.length,
      alternativeWin: alternative?.white,
      alternativeGap: alternative == null ? 0 : moverAfter - alternative.mover,
      previousUci: previousUci,
      simpleRecapture: simpleRecapture,
      judgement: playedIsBest
          ? null
          : lichessJudgementForWinningChanceLoss(
              (moverBefore - moverAfter) / 50,
            ),
      likelyOpeningBook: () => _isTobyLikelyOpeningMove(
        ply: moves.length,
        startFen: start,
        beforeFen: () => fen,
        san: candidate.san,
        uci: uci,
      ),
    ));
    if (grade != null) grades[uci] = grade;
  }
  return grades;
}

typedef _TobyMoveEvidence = ({
  String beforeFen,
  String uci,
  String san,
  bool isWhite,
  double beforeWin,
  double afterWin,
  double moverChange,
  bool playedIsBest,
  int lineCount,
  double? alternativeWin,
  double alternativeGap,
  String? previousUci,
  bool simpleRecapture,
  LichessJudgement? judgement,
  bool Function() likelyOpeningBook,
});

// Mirrors Desktop's classifyReportMoveEvidence for the evidence actually
// supplied by Toby. No engine searches, previous report verdicts or book I/O.
GameMoveClassification? _classifyTobyMove(_TobyMoveEvidence e) {
  final isWhite = e.isWhite;
  final beforeWin = e.beforeWin;
  final afterWin = e.afterWin;
  final moverChange = e.moverChange;
  final playedIsBest = e.playedIsBest;

  final moverBefore = isWhite ? beforeWin : (100 - beforeWin);
  final moverAfter = isWhite ? afterWin : (100 - afterWin);

  // No positive badge without an alternative or for a loss beyond the
  // largest tolerated drop. Skip all board-fact work in either case.
  if (e.lineCount <= 1 || moverChange < -2) {
    return _tobyError(
      judgement: e.judgement,
      moverChange: moverChange,
      moverBefore: moverBefore,
      moverAfter: moverAfter,
    );
  }

  final alternativeWin = e.alternativeWin;
  final alternativeMoverWin = alternativeWin == null
      ? null
      : (isWhite ? alternativeWin : (100 - alternativeWin));
  final alternativeGap = e.alternativeGap;
  final simpleRecapture = e.simpleRecapture;

  // ── Steps 2–3: board facts and outcome-band context ────────────────────
  // Derived from the FENs alone, so re-tuning the rules below never needs a
  // fresh engine run.
  final facts = describeMove(
    beforeFen: e.beforeFen,
    playedUci: e.uci,
    previousUci: e.previousUci,
  );

  // Routine and forced moves veto *positive* labels only. They must still fall
  // through to the judgment — an obvious-looking move can be an inaccuracy or
  // worse, and returning "no symbol" here would hide it.
  var positiveLabelsEligible = !facts.isForcedOrRoutine && !simpleRecapture;

  // Routine material recovery: taking a loose or already-committed unit while
  // conceding nothing, in a position the capture does not actually change.
  // Material balance alone is never the test — a deficit can be real
  // compensation — so board evidence is combined with band and win% movement.
  final routineMaterialRecovery =
      facts.isBoardLevelMaterialRecovery &&
      !escapesClearlyLosingBand(
        moverBefore: moverBefore,
        moverAfter: moverAfter,
      ) &&
      outcomeBandFor(moverAfter).index <= outcomeBandFor(moverBefore).index &&
      moverChange < kRoutinePraiseMinWinGainPp;
  if (routineMaterialRecovery) positiveLabelsEligible = false;

  // Praise floor: below it, an ordinary capture, recapture or retreat has to
  // earn its symbol with a real winning-chance gain or by escaping the
  // clearly-losing band.
  //
  // Scoped to Great and Best only, matching the rule as written. It does not
  // currently change Brilliant either way: [verifyBrilliantMove] independently
  // requires the mover to sit near or above equality after the move, so a !!
  // can never reach this band. That also means a genuine *defensive* brilliancy
  // in a losing position is unreachable today — a known gap, tracked separately
  // rather than papered over here.
  var greatAndBestEligible = positiveLabelsEligible;

  // Once the played move and the first real alternative both keep a clearly
  // won position clearly won, their gap is conversion noise rather than a
  // prestigious decision. Brilliant remains separate: an independently
  // verified exceptional idea may still qualify on its own evidence.
  final saturatedWinningConversion =
      moverBefore >= kBandBetterMax &&
      moverAfter >= kBandBetterMax &&
      alternativeMoverWin != null &&
      alternativeMoverWin >= kBandBetterMax;
  if (saturatedWinningConversion) greatAndBestEligible = false;

  // Do not let routine captures inherit the prestige of the tactic that made
  // them possible. A capture can still earn praise in a competitive position,
  // by crossing an outcome band, or by producing a substantial win% gain.
  final beforeBand = outcomeBandFor(moverBefore);
  final afterBand = outcomeBandFor(moverAfter);
  final routineConversionCapture =
      facts.isCapture &&
      beforeBand == afterBand &&
      beforeBand != OutcomeBand.competitive &&
      moverChange < kRoutinePraiseMinWinGainPp;
  if (routineConversionCapture) greatAndBestEligible = false;

  if (moverAfter <= kPositivePraiseWinFloorPp &&
      (facts.isCapture || facts.isRoutineRetreat || facts.isForcedRecapture)) {
    final earnsException =
        moverChange >= kRoutinePraiseMinWinGainPp ||
        escapesClearlyLosingBand(
          moverBefore: moverBefore,
          moverAfter: moverAfter,
        );
    if (!earnsException) greatAndBestEligible = false;
  }

  // ── Steps 4–7: positive labels ─────────────────────────────────────────
  if (positiveLabelsEligible) {
    if (_isTobyBrilliant(e)) {
      return GameMoveClassification.brilliant;
    }

    // Great: near-best — the only reliable move (meaningful MultiPV gap), a
    // decisive outcome swing, engine-top punishment of the opponent's error,
    // a defensive save, or a clean advantage conversion where natural
    // alternatives slip. Defensive saves may still sit under 50% after the
    // move (partial recovery); other paths keep the losing/alt-crushing veto.
    if (greatAndBestEligible && moverChange >= -2 && alternativeWin != null) {
      final defensiveSave = _isDefensiveSave(
        playedIsBest: playedIsBest,
        moverBefore: moverBefore,
        moverAfter: moverAfter,
        alternativeGap: alternativeGap,
      );
      final notLosingOrCrushing = !_isLosingOrAlternateCrushing(
        afterWin: afterWin,
        alternativeWin: alternativeWin,
        isWhite: isWhite,
      );
      if (defensiveSave || notLosingOrCrushing) {
        final onlyGoodMove = alternativeGap >= kGreatOnlyGoodMoveGapPp;
        final outcomeSwing = _hasChangedGameOutcome(
          beforeWin: beforeWin,
          afterWin: afterWin,
          isWhite: isWhite,
          moverChange: moverChange,
        );
        final advantageConversion = _isAdvantageConversion(
          playedIsBest: playedIsBest,
          moverBefore: moverBefore,
          moverAfter: moverAfter,
          alternativeMoverWin: alternativeMoverWin!,
          alternativeGap: alternativeGap,
        );
        if (defensiveSave ||
            (notLosingOrCrushing &&
                (onlyGoodMove || outcomeSwing || advantageConversion))) {
          return GameMoveClassification.bestMove;
        }
      }
    }

    // Best: being PV1 is not sufficient on its own. The next playable
    // alternative has to be meaningfully worse, and the position has to still
    // be contested — unless the move is itself a substantial defensive
    // recovery.
    if (greatAndBestEligible && playedIsBest && moverChange >= -2) {
      final band = outcomeBandFor(moverBefore);
      final contested =
          band == OutcomeBand.competitive ||
          band == OutcomeBand.worse ||
          band == OutcomeBand.better;
      final recovers = escapesClearlyLosingBand(
        moverBefore: moverBefore,
        moverAfter: moverAfter,
      );
      final hasMoat =
          alternativeWin == null || alternativeGap >= kBestRequiredPvMoatPp;
      if ((contested || recovers) && hasMoat) {
        return GameMoveClassification.goodMove;
      }
    }
  }

  // ── Steps 8–11 ─────────────────────────────────────────────────────────
  return _tobyError(
    judgement: e.judgement,
    moverChange: moverChange,
    moverBefore: moverBefore,
    moverAfter: moverAfter,
  );
}

GameMoveClassification? _tobyError({
  required LichessJudgement? judgement,
  required double moverChange,
  required double moverBefore,
  required double moverAfter,
}) {
  final retainedDecisiveWin =
      moverBefore >= kDecisiveWinNoErrorFloorPp &&
      moverAfter >= kDecisiveWinNoErrorFloorPp;
  final retainedDecisiveLoss =
      moverBefore <= kDecisiveLossNoErrorCeilingPp &&
      moverAfter <= kDecisiveLossNoErrorCeilingPp;
  if (retainedDecisiveWin || retainedDecisiveLoss) {
    return null;
  }

  if (judgement == null) return null;

  // ── Missed Win ─────────────────────────────────────────────────────────
  // Ours, not lichess's, and deliberately gated behind a judgment: it only ever
  // *renames* an error lichess already found, so the set of moves carrying a
  // negative symbol stays exactly lichess's set. A missed conversion after the
  // opponent's blunder, then throwing a clear win outright.
  if (moverBefore >= 75 && moverAfter <= 55 && moverChange <= -15) {
    return GameMoveClassification.missedWin;
  }

  return switch (judgement) {
    LichessJudgement.inaccuracy => GameMoveClassification.inaccuracy,
    LichessJudgement.mistake => GameMoveClassification.mistake,
    LichessJudgement.blunder => GameMoveClassification.blunder,
  };
}

bool _isTobyBrilliant(_TobyMoveEvidence e) {
  final isWhite = e.isWhite;
  final beforeWin = e.beforeWin;
  final afterWin = e.afterWin;
  final moverChange = e.moverChange;
  final alternativeWin = e.alternativeWin;
  final alternativeGap = e.alternativeGap;

  // ── Hard exclusions ────────────────────────────────────────────────────
  if (e.san.contains('=')) return false;
  if (e.simpleRecapture) return false;
  // The caller already excluded routine moves and simple recaptures.
  if (e.likelyOpeningBook()) return false;
  if (isReportCompletelyDecidedForBrilliant(
    beforeWin: beforeWin,
    afterWin: afterWin,
    isWhite: isWhite,
  )) {
    return false;
  }
  if (alternativeWin != null &&
      _isLosingOrAlternateCrushing(
        afterWin: afterWin,
        alternativeWin: alternativeWin,
        isWhite: isWhite,
      )) {
    return false;
  }
  final losing = isWhite ? afterWin < 48 : afterWin > 52;
  if (losing) return false;

  // ── Engine-best or effectively tied ────────────────────────────────────
  final tiedForBest = moverChange >= -kBrilliantMaxLossPp;
  if (!e.playedIsBest && !tiedForBest) return false;
  if (moverChange < -kBrilliantMaxLossPp) return false;

  // Need MultiPV alternatives for prestige; single-line "only move" is not !!.
  if (e.lineCount < 2 || alternativeWin == null) return false;

  // Clear edge over ordinary alternatives, or a uniquely strong only-move.
  final onlyMoveResource = alternativeGap >= 12;
  final meaningfulGap = alternativeGap >= kBrilliantMinAlternativeGapPp;
  if (!onlyMoveResource && !meaningfulGap) return false;

  // ── Material / tactical investment ─────────────────────────────────────
  // Toby supplies no continuation; use Desktop's board-only investment check.
  return isMeaningfulBrilliantInvestment(e.beforeFen, e.uci, const <String>[]);
}

bool _isTobyLikelyOpeningMove({
  required int ply,
  required String startFen,
  required String Function() beforeFen,
  required String san,
  required String uci,
}) {
  if (ply >= kBrilliantOpeningPlyLimit) return false;
  if (_sidePieceCount(startFen) <= 12) return false;
  // Quiet early moves in a full opening are book-like.
  final tactical = san.contains('x') || san.contains('+') || san.contains('#');
  if (!tactical) return true;
  // Early pawn gambits (even with captures) are not prestigious !! material.
  try {
    final pos = Chess.fromSetup(Setup.parseFen(beforeFen()));
    final played = NormalMove.fromUci(uci);
    if (!pos.isLegal(played)) return true;
    final piece = pos.board.pieceAt(played.from);
    if (piece?.role == Role.pawn) return true;
  } catch (_) {
    return true;
  }
  return false;
}
