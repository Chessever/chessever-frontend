// Pure control-flow helpers for board evaluation restarts.
//
// Separates "this position needs an evaluation result" from "restart
// evaluation even if the same FEN already has a complete or in-flight
// result". Used to stop same-FEN thrash (CASCADE APPLY complete → new
// evaluation request loop) during rapid opening-explorer move scrubbing.
//
// Also owns MultiPV-width + minimum-depth completeness, non-shrinking PV
// merge (multi-ply retention), and deepen-eligibility so a 1-half-move /
// shallow settle cannot permanently pin the panel while depth should climb.

import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:dartchess/dartchess.dart';

/// Depth below which a non-mate board settle is still interim: MultiPV may be
/// full width but each line is often a single half-move, and short-circuiting
/// restarts freezes the depth display.
const int boardEvalMinCompleteDepth = 12;

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

/// Effective MultiPV width the board must reach before a result is "complete".
///
/// Caps [configuredMultiPv] by [maxLegalLines] when the position simply cannot
/// produce that many distinct principal variations (e.g. only 2 legal moves).
int boardEvalTargetPvWidth({
  required int configuredMultiPv,
  int? maxLegalLines,
}) {
  final target = configuredMultiPv <= 0 ? 1 : configuredMultiPv;
  if (maxLegalLines == null) return target;
  if (maxLegalLines <= 0) return 0;
  return maxLegalLines < target ? maxLegalLines : target;
}

/// Whether the settled search depth is still too shallow to treat as finished.
///
/// Mate positions never need more depth for restart purposes.
bool boardEvalNeedsMoreDepth({
  required int reachedDepth,
  int minCompleteDepth = boardEvalMinCompleteDepth,
  bool isMate = false,
}) {
  if (isMate) return false;
  if (minCompleteDepth <= 0) return false;
  return reachedDepth < minCompleteDepth;
}

/// Whether [principalVariations] already constitute a finished, usable result
/// for [currentBoardFen] under the current multiPV setting and depth.
///
/// A finished result means: not still evaluating, base FEN matches the board,
/// line count meets the configured MultiPV width (or the legal-move cap), and
/// reached depth is past the interim floor (unless waived / mate). Incomplete
/// width or shallow interim settles must NOT short-circuit local deepening —
/// that pinned the panel at one half-move while depth froze.
///
/// [waiveWidthRequirement] covers mate / terminal cloud settles where a single
/// forced line is the entire usable result and re-searching would thrash.
bool hasCompleteUsableBoardEval({
  required String? principalVariationsBaseFen,
  required int principalVariationCount,
  required String currentBoardFen,
  required bool isEvaluating,
  required String Function(String fen) normalizeFen,
  int configuredMultiPv = 1,
  int? maxLegalLines,
  bool waiveWidthRequirement = false,
  int? reachedDepth,
  int minCompleteDepth = boardEvalMinCompleteDepth,
}) {
  if (isEvaluating) return false;
  if (principalVariationCount <= 0) return false;
  final base = principalVariationsBaseFen;
  if (base == null || base.trim().isEmpty) return false;
  if (normalizeFen(base) != normalizeFen(currentBoardFen)) return false;

  if (waiveWidthRequirement) return true;

  final targetWidth = boardEvalTargetPvWidth(
    configuredMultiPv: configuredMultiPv,
    maxLegalLines: maxLegalLines,
  );
  // Game-over / no legal moves: any non-empty PV set for the FEN is enough
  // (callers usually skip eval entirely on terminal positions).
  if (targetWidth <= 0) return true;
  if (principalVariationCount < targetWidth) return false;

  // Full MultiPV at a shallow interim depth is not finished — half-move-only
  // lines and a frozen depth display are the user-visible failure mode.
  if (reachedDepth != null &&
      boardEvalNeedsMoreDepth(
        reachedDepth: reachedDepth,
        minCompleteDepth: minCompleteDepth,
      )) {
    return false;
  }

  return true;
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

/// Merge progressive / cascade PV frames without shrinking the panel and
/// without collapsing multi-ply lines to a single half-move snapshot.
///
/// A degraded frame (partial MultiPV snapshot, short early-depth PV, or a line
/// whose conversion failed mid-tail) keeps previously known same-position lines
/// beyond its own length and prefers the longer move list when the incoming
/// line is a prefix of the previous one. Call sites clear [previous] on
/// position change.
List<AnalysisLine> mergeBoardPvProgress(
  List<AnalysisLine> previous,
  List<AnalysisLine> incoming,
) {
  if (incoming.isEmpty) return incoming;
  final merged = <AnalysisLine>[];
  for (var i = 0; i < incoming.length; i++) {
    final newLine = incoming[i];
    final prevLine = i < previous.length ? previous[i] : null;
    if (prevLine == null) {
      merged.add(newLine);
      continue;
    }
    final prevMoves = prevLine.moves;
    final newMoves = newLine.moves;

    // Prefer longer multi-ply continuity when the new frame is only a prefix
    // (common at the first multipv line of a new depth: one half-move lands
    // before the rest of the PV is filled in).
    if (prevMoves.isNotEmpty &&
        newMoves.isNotEmpty &&
        prevMoves.length > newMoves.length &&
        _isPrefixMoves(newMoves, prevMoves)) {
      merged.add(
        AnalysisLine(
          moves: prevLine.moves,
          sanMoves: prevLine.sanMoves,
          evaluation: newLine.evaluation,
          mate: newLine.mate,
        ),
      );
      continue;
    }

    // Same first move, incoming is a single half-move while previous is a
    // multi-ply line — keep the multi-ply body rather than flashing one ply.
    if (prevMoves.length > 1 &&
        newMoves.length == 1 &&
        prevMoves.first.uci == newMoves.first.uci) {
      merged.add(
        AnalysisLine(
          moves: prevLine.moves,
          sanMoves: prevLine.sanMoves,
          evaluation: newLine.evaluation,
          mate: newLine.mate,
        ),
      );
      continue;
    }

    merged.add(newLine);
  }
  for (var i = incoming.length; i < previous.length; i++) {
    merged.add(previous[i]);
  }
  return merged;
}

/// Whether a finished settle should schedule another search to grow MultiPV
/// width (used by the board provider after stockfish returns).
///
/// Depth-only shallowness after a natural budget exhaust is NOT retried —
/// that would thrash. Depth continues within a single live search while
/// [isEvaluating] stays true; artificial 10s / 800ms caps that froze depth
/// are removed at the call site instead.
bool boardEvalShouldRetryAfterSettle({
  required int principalVariationCount,
  required int configuredMultiPv,
  int? maxLegalLines,
  bool isMate = false,
}) {
  if (isMate) return false;
  final targetWidth = boardEvalTargetPvWidth(
    configuredMultiPv: configuredMultiPv,
    maxLegalLines: maxLegalLines,
  );
  if (targetWidth <= 0) return false;
  return principalVariationCount < targetWidth;
}

/// Whether a full-width settle at [reachedDepth] should still be treated as
/// interim for short-circuit purposes (search still had budget / was truncated).
///
/// Call with [searchStillActiveOrTruncated] true only when the live search was
/// cut short. Natural budget exhaust passes false so depth-10 after a 5s user
/// setting is complete.
bool boardEvalShallowSettleBlocksComplete({
  required int reachedDepth,
  required bool searchStillActiveOrTruncated,
  int minCompleteDepth = boardEvalMinCompleteDepth,
  bool isMate = false,
}) {
  if (!searchStillActiveOrTruncated) return false;
  return boardEvalNeedsMoreDepth(
    reachedDepth: reachedDepth,
    minCompleteDepth: minCompleteDepth,
    isMate: isMate,
  );
}

bool _isPrefixMoves(List<Move> shorter, List<Move> longer) {
  if (shorter.length > longer.length) return false;
  for (var i = 0; i < shorter.length; i++) {
    if (shorter[i].uci != longer[i].uci) return false;
  }
  return true;
}
