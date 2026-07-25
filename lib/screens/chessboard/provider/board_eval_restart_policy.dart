// Pure control-flow helpers for board evaluation restarts.
//
// Separates "this position needs an evaluation result" from "restart
// evaluation even if the same FEN already has a complete or in-flight
// result". Used to stop same-FEN thrash (CASCADE APPLY complete → new
// evaluation request loop) during rapid opening-explorer move scrubbing.

enum BoardEvalStartAction {
  /// Start (or restart) evaluation for the requested key.
  start,

  /// An identical evaluation is already running; let it finish.
  coalesceInFlight,

  /// Complete usable multiPV is already applied for this position; no-op.
  skipAlreadyComplete,
}

class BoardEvalStartDecision {
  final BoardEvalStartAction action;
  final String reason;

  const BoardEvalStartDecision({required this.action, required this.reason});

  bool get shouldStart => action == BoardEvalStartAction.start;
}

/// Whether [principalVariations] already constitute a finished, usable result
/// for [currentBoardFen] under the current multiPV setting.
///
/// A finished result means: not still evaluating, base FEN matches the board,
/// and at least one PV line is present. Callers that need a deeper/local search
/// after a shallow cloud hit must keep [isEvaluating] true until that search
/// completes (so this returns false and in-flight coalescing applies instead).
bool hasCompleteUsableBoardEval({
  required String? principalVariationsBaseFen,
  required int principalVariationCount,
  required int requiredPrincipalVariationCount,
  required String currentBoardFen,
  required bool isEvaluating,
  required String Function(String fen) normalizeFen,
}) {
  if (isEvaluating) return false;
  if (principalVariationCount < requiredPrincipalVariationCount.clamp(1, 5)) {
    return false;
  }
  final base = principalVariationsBaseFen;
  if (base == null || base.trim().isEmpty) return false;
  return normalizeFen(base) == normalizeFen(currentBoardFen);
}

/// Decide whether a board eval entry-point should start work for [requestedCacheKey].
///
/// [forceRestart] is reserved for true re-eval intents (engine settings / multiPV
/// change, threats toggle, stalled-watchdog recovery). Ordinary [force] used by
/// navigation / visible-page scheduling must NOT bypass same-FEN coalesce or
/// complete-result short-circuit — that is what caused unbounded cascade restarts.
BoardEvalStartDecision decideBoardEvalStart({
  required String requestedCacheKey,
  required String? activeEvalKey,
  required bool hasActiveRequest,
  required bool activeRequestIsStale,
  required bool hasCompleteUsableResultForKey,
  required bool forceRestart,
}) {
  if (forceRestart) {
    return const BoardEvalStartDecision(
      action: BoardEvalStartAction.start,
      reason: 'forceRestart',
    );
  }

  if (hasActiveRequest &&
      activeEvalKey == requestedCacheKey &&
      !activeRequestIsStale) {
    return const BoardEvalStartDecision(
      action: BoardEvalStartAction.coalesceInFlight,
      reason: 'already evaluating same position',
    );
  }

  if (hasCompleteUsableResultForKey) {
    return const BoardEvalStartDecision(
      action: BoardEvalStartAction.skipAlreadyComplete,
      reason: 'complete multiPV already applied for this FEN',
    );
  }

  return const BoardEvalStartDecision(
    action: BoardEvalStartAction.start,
    reason: 'needs evaluation',
  );
}
