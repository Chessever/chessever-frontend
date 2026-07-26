import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// Board-derived facts about one played move, plus the outcome-band model the
/// classifier reasons over.
///
/// Everything in this file is recomputed from FEN + UCI alone — no engine
/// evidence. That is deliberate: when classification rules are re-tuned against
/// a cached analysis snapshot, these facts can be rebuilt exactly, so a rule
/// change never needs a fresh Stockfish run. Only candidate *evaluations* are
/// unavailable offline, and those already live in the snapshot.
///
/// The facts are exposed as individual components rather than a single opaque
/// "this move was routine" boolean so a rejected label can explain precisely
/// which condition disqualified it, and so a false suppression is diagnosable.

/// Standard material values. Kings are sentinel-valued and excluded from
/// balance arithmetic.
int reportPieceValue(Role role) => switch (role) {
  Role.pawn => 1,
  Role.knight || Role.bishop => 3,
  Role.rook => 5,
  Role.queen => 9,
  Role.king => 100,
};

/// White-relative material balance, kings excluded.
int reportMaterialBalanceWhite(Position position) {
  var score = 0;
  for (final square in Square.values) {
    final piece = position.board.pieceAt(square);
    if (piece == null || piece.role == Role.king) continue;
    final value = reportPieceValue(piece.role);
    score += piece.color == Side.white ? value : -value;
  }
  return score;
}

/// One-exchange static exchange evaluation on [square].
///
/// The opponent captures with their cheapest attacker and [owner] recaptures
/// with their cheapest defender if one exists. Returns true when the exchange
/// leaves [owner] down at least a minor piece, i.e. the unit is genuinely
/// hanging or underprotected rather than sitting on an attacked-but-defended
/// square where the trade is fair.
///
/// [position] must be the position with the *opponent* to move.
bool isNetHangingPiece(
  Position position, {
  required Square square,
  required Side owner,
}) {
  final ourPiece = position.board.pieceAt(square);
  if (ourPiece == null || ourPiece.color != owner) return false;
  final ourValue = reportPieceValue(ourPiece.role);
  if (ourValue < 3) return false;

  final opponent = owner == Side.white ? Side.black : Side.white;
  ({Square from, int value})? cheapestAttacker;
  for (final from in Square.values) {
    final piece = position.board.pieceAt(from);
    if (piece == null || piece.color != opponent) continue;
    final candidate = NormalMove(from: from, to: square);
    if (!position.isLegal(candidate)) continue;
    final value = reportPieceValue(piece.role);
    if (cheapestAttacker == null || value < cheapestAttacker.value) {
      cheapestAttacker = (from: from, value: value);
    }
  }
  if (cheapestAttacker == null) return false;

  final afterCapture = position.play(
    NormalMove(from: cheapestAttacker.from, to: square),
  );
  var canRecapture = false;
  for (final from in Square.values) {
    final piece = afterCapture.board.pieceAt(from);
    if (piece == null || piece.color != owner) continue;
    if (!afterCapture.isLegal(NormalMove(from: from, to: square))) continue;
    canRecapture = true;
    break;
  }

  if (!canRecapture) return true;
  return (-ourValue + cheapestAttacker.value) <= -3;
}

/// Whether [side]'s piece standing on [square] is attacked by the opponent,
/// regardless of whose turn it is. Uses raw attack maps rather than legal-move
/// generation so it works before the move as well as after.
bool isSquareAttackedBy(Position position, Square square, Side attacker) =>
    position.board.attacksTo(square, attacker).isNotEmpty;

/// How many of [side]'s units defend [square].
int defenderCount(Position position, Square square, Side side) =>
    position.board.attacksTo(square, side).size;

/// Outcome bands, in mover-relative winning-chance percentage points.
///
/// Bands exist so the classifier can talk about "escaped the losing band" or
/// "the position did not meaningfully change" without re-deriving thresholds at
/// each call site. Boundaries are versioned here so a tuning change is one edit.
enum OutcomeBand {
  clearlyLosing,
  worse,
  competitive,
  better,
  clearlyWinning;

  bool get isClearlyLosing => this == OutcomeBand.clearlyLosing;
}

/// Band boundaries (mover winning chance, percentage points).
const double kBandClearlyLosingMax = 10;
const double kBandWorseMax = 25;
const double kBandCompetitiveMax = 75;
const double kBandBetterMax = 90;

/// Dead-zone applied when asking whether a move *changed* band, so a position
/// resting on a boundary does not flip labels under trivial engine noise.
const double kBandHysteresisPp = 2;

OutcomeBand outcomeBandFor(double moverWinPercent) {
  if (moverWinPercent <= kBandClearlyLosingMax) return OutcomeBand.clearlyLosing;
  if (moverWinPercent <= kBandWorseMax) return OutcomeBand.worse;
  if (moverWinPercent < kBandCompetitiveMax) return OutcomeBand.competitive;
  if (moverWinPercent < kBandBetterMax) return OutcomeBand.better;
  return OutcomeBand.clearlyWinning;
}

/// Bands no longer gate the negative labels at all: `?!`, `?` and `??` come from
/// the lichess port, which does its own softening in winning-chance space. What
/// is left here serves the *positive* labels, which still need to know whether a
/// position is contested and whether a move dragged the mover out of a lost one.
///
/// The two band helpers that used to sit here — a "collapsed into a worse band"
/// test and a decided-game amnesty — were both scaffolding around measuring
/// damage in win-percentage points. Reintroducing either would put a second,
/// competing judgment back next to lichess's.

/// True when the mover climbed out of [OutcomeBand.clearlyLosing].
bool escapesClearlyLosingBand({
  required double moverBefore,
  required double moverAfter,
}) =>
    outcomeBandFor(moverBefore).isClearlyLosing &&
    !outcomeBandFor(moverAfter).isClearlyLosing &&
    (moverAfter - moverBefore) > kBandHysteresisPp;

/// Board-derived description of a single played move.
@immutable
class MovePositionFacts {
  const MovePositionFacts({
    required this.isCapture,
    required this.captureValue,
    required this.movedPieceValue,
    required this.isPromotion,
    required this.givesCheck,
    required this.wasInCheckBefore,
    required this.isOnlyLegalMove,
    required this.movedPieceWasAttacked,
    required this.movedPieceWasHanging,
    required this.landsSafely,
    required this.isOnlySafePieceMove,
    required this.isRecaptureOnLastCaptureSquare,
    required this.capturedPieceWasLoose,
    required this.materialBeforeForMover,
    required this.materialAfterForMover,
  });

  /// Fail-open neutral value: used when a FEN or UCI cannot be parsed, so a
  /// parse failure can never silently assert that a move was routine.
  static const MovePositionFacts unknown = MovePositionFacts(
    isCapture: false,
    captureValue: 0,
    movedPieceValue: 0,
    isPromotion: false,
    givesCheck: false,
    wasInCheckBefore: false,
    isOnlyLegalMove: false,
    movedPieceWasAttacked: false,
    movedPieceWasHanging: false,
    landsSafely: false,
    isOnlySafePieceMove: false,
    isRecaptureOnLastCaptureSquare: false,
    capturedPieceWasLoose: false,
    materialBeforeForMover: 0,
    materialAfterForMover: 0,
  );

  final bool isCapture;
  final int captureValue;
  final int movedPieceValue;
  final bool isPromotion;
  final bool givesCheck;

  /// The mover was in check before playing, so this move is a check evasion.
  final bool wasInCheckBefore;

  /// The position offered exactly one legal move — genuinely forced.
  final bool isOnlyLegalMove;

  /// The moved piece stood on a square the opponent attacked.
  final bool movedPieceWasAttacked;

  /// The moved piece was not merely attacked but losing material if left.
  final bool movedPieceWasHanging;

  /// After the move, the piece is not net-hanging on its destination.
  final bool landsSafely;

  /// Of every legal move that piece had, this was the only one reaching a safe
  /// square — an escape with no alternative rather than a chosen resource.
  final bool isOnlySafePieceMove;

  /// This move captures on the square the opponent's previous move captured on.
  final bool isRecaptureOnLastCaptureSquare;

  /// The captured unit was undefended, so taking it required no calculation.
  final bool capturedPieceWasLoose;

  /// Material from the mover's point of view, kings excluded.
  final int materialBeforeForMover;
  final int materialAfterForMover;

  /// The mover ended the move down material relative to the opponent.
  bool get moverIsMateriallyWorse => materialAfterForMover < 0;

  /// The move handed material back rather than winning any.
  bool get givesMaterialBack => materialAfterForMover < materialBeforeForMover;

  /// A forced reply to check: either the only legal move, or an evasion that
  /// simply steps out of an attack without capturing anything.
  bool get isForcedCheckEvasion =>
      wasInCheckBefore && (isOnlyLegalMove || !isCapture);

  /// Taking back on the square just captured, where declining would leave the
  /// mover down the traded material.
  bool get isForcedRecapture =>
      isRecaptureOnLastCaptureSquare && captureValue > 0;

  /// An attacked piece stepping away to safety with no other content — no
  /// capture, no check, and nothing else was available to it.
  bool get isRoutineRetreat =>
      movedPieceWasAttacked &&
      !isCapture &&
      !givesCheck &&
      !isPromotion &&
      landsSafely;

  /// Any board-level reason the move is ordinary rather than chosen. This
  /// gates *positive* labels only — a routine move can still be an error.
  bool get isForcedOrRoutine =>
      isOnlyLegalMove ||
      isForcedCheckEvasion ||
      isForcedRecapture ||
      isRoutineRetreat;

  /// Board half of "routine material recovery": grabbing a loose or already
  /// committed unit while conceding nothing. The classifier pairs this with
  /// winning-chance and outcome-band evidence before suppressing praise,
  /// because a material deficit can be genuine compensation.
  bool get isBoardLevelMaterialRecovery =>
      isCapture && capturedPieceWasLoose && !givesMaterialBack && !isPromotion;
}

/// Builds [MovePositionFacts] for the move [playedUci] made in [beforeFen].
///
/// [previousUci] is the opponent's preceding move, used only to recognise a
/// recapture; pass null at the start of a game.
MovePositionFacts describeMove({
  required String beforeFen,
  required String playedUci,
  String? previousUci,
}) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(beforeFen));
    final move = NormalMove.fromUci(playedUci);
    if (!position.isLegal(move)) return MovePositionFacts.unknown;

    final mover = position.turn;
    final opponent = mover == Side.white ? Side.black : Side.white;
    final moving = position.board.pieceAt(move.from);
    if (moving == null) return MovePositionFacts.unknown;

    final captured = position.board.pieceAt(move.to);
    final after = position.play(move);

    final materialBeforeWhite = reportMaterialBalanceWhite(position);
    final materialAfterWhite = reportMaterialBalanceWhite(after);
    final sign = mover == Side.white ? 1 : -1;

    // Legal-move census: "forced" means the rules left exactly one option.
    var legalMoveCount = 0;
    for (final from in Square.values) {
      final piece = position.board.pieceAt(from);
      if (piece == null || piece.color != mover) continue;
      legalMoveCount += position.legalMovesOf(from).size;
      if (legalMoveCount > 1) break;
    }

    // Of this piece's own options, how many reach a square where it is not
    // net-hanging? Exactly one means the escape had no alternative.
    var safeDestinations = 0;
    for (final to in position.legalMovesOf(move.from).squares) {
      final candidate = NormalMove(from: move.from, to: to);
      if (!position.isLegal(candidate)) continue;
      final probe = position.play(candidate);
      if (!isNetHangingPiece(probe, square: to, owner: mover)) {
        safeDestinations++;
        if (safeDestinations > 1) break;
      }
    }

    final landsSafely = !isNetHangingPiece(
      after,
      square: move.to,
      owner: mover,
    );

    final wasAttacked = isSquareAttackedBy(position, move.from, opponent);
    final wasHanging =
        wasAttacked &&
        reportPieceValue(moving.role) >= 3 &&
        defenderCount(position, move.from, mover) == 0;

    final previousTo =
        previousUci == null ? null : NormalMove.fromUci(previousUci).to;

    return MovePositionFacts(
      isCapture: captured != null,
      captureValue: captured == null ? 0 : reportPieceValue(captured.role),
      movedPieceValue: reportPieceValue(moving.role),
      isPromotion: move.promotion != null,
      givesCheck: after.isCheck,
      wasInCheckBefore: position.isCheck,
      isOnlyLegalMove: legalMoveCount <= 1,
      movedPieceWasAttacked: wasAttacked,
      movedPieceWasHanging: wasHanging,
      landsSafely: landsSafely,
      isOnlySafePieceMove: safeDestinations <= 1 && landsSafely,
      isRecaptureOnLastCaptureSquare:
          previousTo != null && previousTo == move.to && captured != null,
      capturedPieceWasLoose:
          captured != null &&
          defenderCount(position, move.to, opponent) == 0,
      materialBeforeForMover: materialBeforeWhite * sign,
      materialAfterForMover: materialAfterWhite * sign,
    );
  } catch (_) {
    return MovePositionFacts.unknown;
  }
}
