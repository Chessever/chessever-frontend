import 'dart:async';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@immutable
class MobileGameReviewState {
  const MobileGameReviewState({
    this.reportState = const GameReportState(),
    this.fingerprint,
    this.revealedFingerprint,
    this.isEligible = false,
    this.unavailableMessage,
  });

  final GameReportState reportState;
  final String? fingerprint;
  final String? revealedFingerprint;
  final bool isEligible;
  final String? unavailableMessage;

  /// Whether classifications have been revealed for this game (sheet open and/or
  /// completed report). Notation attach uses
  /// [shouldShowReportClassificationsOnBoard] /
  /// [reportClassificationsForNotationAttach], which key off a completed
  /// matching report without requiring the sheet.
  bool get classificationsRevealed {
    if (fingerprint == null) return false;
    if (fingerprint == revealedFingerprint) return true;
    final report = reportState.report;
    return reportState.status == GameReportStatus.completed &&
        report != null &&
        report.fingerprint == fingerprint;
  }

  /// Whether the Game Analysis entry point should be shown at all. A live or
  /// move-less game offers nothing to analyze yet, so the button (and its
  /// "starts when the game ends" copy) is hidden until there is a real report
  /// to run or show.
  bool get shouldOfferAnalysis =>
      isEligible || reportState.status != GameReportStatus.idle;

  MobileGameReviewState copyWith({
    GameReportState? reportState,
    String? fingerprint,
    String? revealedFingerprint,
    bool? isEligible,
    String? unavailableMessage,
    bool clearRevealed = false,
    bool clearUnavailableMessage = false,
  }) {
    return MobileGameReviewState(
      reportState: reportState ?? this.reportState,
      fingerprint: fingerprint ?? this.fingerprint,
      revealedFingerprint:
          clearRevealed
              ? null
              : (revealedFingerprint ?? this.revealedFingerprint),
      isEligible: isEligible ?? this.isEligible,
      unavailableMessage:
          clearUnavailableMessage
              ? null
              : (unavailableMessage ?? this.unavailableMessage),
    );
  }

  /// Value equality so [StateNotifierProvider] / `select` only rebuild when
  /// review fields that affect UI actually change (Riverpod best practice).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MobileGameReviewState &&
        fingerprint == other.fingerprint &&
        revealedFingerprint == other.revealedFingerprint &&
        isEligible == other.isEligible &&
        unavailableMessage == other.unavailableMessage &&
        reportState.status == other.reportState.status &&
        reportState.progress == other.reportState.progress &&
        reportState.completedPositions == other.reportState.completedPositions &&
        reportState.totalPositions == other.reportState.totalPositions &&
        reportState.message == other.reportState.message &&
        identical(reportState.report, other.reportState.report);
  }

  @override
  int get hashCode => Object.hash(
    fingerprint,
    revealedFingerprint,
    isEligible,
    unavailableMessage,
    reportState.status,
    reportState.progress,
    reportState.completedPositions,
    reportState.totalPositions,
    reportState.message,
    reportState.report,
  );
}

/// Coordinates whole-game analysis for one board page.
///
/// Implemented as a [StateNotifier] (not [ChangeNotifier]) so Riverpod rebuilds
/// consumers when [state] is assigned — including after report completion when
/// notation must attach classification icons without opening the sheet.
class MobileGameReviewController
    extends StateNotifier<MobileGameReviewState> {
  static const Duration defaultAutoStartDelay = Duration(seconds: 2);

  MobileGameReviewController({
    GameAnalysisReportController? reportController,
    Duration autoStartDelay = defaultAutoStartDelay,
  }) : _reportController = reportController ?? GameAnalysisReportController(),
       _autoStartDelay = autoStartDelay,
       super(const MobileGameReviewState()) {
    _reportController.addListener(_onReportChanged);
  }

  final GameAnalysisReportController _reportController;
  /// Extra listenable for modal sheet [AnimatedBuilder] (sheet is not a
  /// Riverpod consumer). Riverpod UI still watches [state] via the provider.
  final _ReviewSheetListenable _sheetListenable = _ReviewSheetListenable();
  ChessGame? _game;
  int? _whiteRating;
  int? _blackRating;
  bool _active = false;
  Timer? _autoStartTimer;
  final Duration _autoStartDelay;

  /// Listenable for the review bottom sheet only. Prefer [ref.watch] on
  /// [mobileGameReviewProvider] for board/notation.
  Listenable get listenable => _sheetListenable;

  /// Public snapshot for sheet/tests. Board/notation should [ref.watch] the
  /// provider state instead of reading this from a held notifier reference.
  MobileGameReviewState get reviewState => state;

  void _emit(MobileGameReviewState next) {
    state = next;
    _sheetListenable.tick();
  }

  void configure({
    required ChessGame game,
    required bool active,
    required bool finished,
    required int whiteRating,
    required int blackRating,
  }) {
    if (!mounted) return;
    final fingerprint = gameReportFingerprint(game);
    final changed = fingerprint != state.fingerprint;
    _game = game;
    _whiteRating = whiteRating > 0 ? whiteRating : null;
    _blackRating = blackRating > 0 ? blackRating : null;
    _active = active;

    if (changed) {
      _autoStartTimer?.cancel();
      _reportController.invalidate();
      _emit(
        MobileGameReviewState(
          fingerprint: fingerprint,
          isEligible: finished && game.mainline.isNotEmpty,
          unavailableMessage: _unavailableMessage(
            finished: finished,
            hasMoves: game.mainline.isNotEmpty,
          ),
        ),
      );
      // A finished game already analyzed this session is restored instantly
      // (and its classifications revealed) instead of being recomputed.
      if (state.isEligible) {
        _reportController.loadCachedReport(fingerprint);
      }
    } else {
      final eligible = finished && game.mainline.isNotEmpty;
      final message = _unavailableMessage(
        finished: finished,
        hasMoves: game.mainline.isNotEmpty,
      );
      if (state.isEligible != eligible || state.unavailableMessage != message) {
        _emit(
          state.copyWith(
            isEligible: eligible,
            unavailableMessage: message,
            clearUnavailableMessage: message == null,
          ),
        );
      }
    }

    if (!active) {
      _autoStartTimer?.cancel();
      if (_reportController.state.isRunning) {
        unawaited(_reportController.cancel());
      }
      return;
    }
    if (state.isEligible &&
        (_reportController.state.status == GameReportStatus.idle ||
            _reportController.state.status == GameReportStatus.cancelled)) {
      _scheduleAnalyze();
    }
  }

  void setActive(bool active) {
    if (!mounted || _active == active) return;
    _active = active;
    if (!active) {
      _autoStartTimer?.cancel();
      if (_reportController.state.isRunning) {
        unawaited(_reportController.cancel());
      }
      return;
    }
    if (state.isEligible &&
        (_reportController.state.status == GameReportStatus.idle ||
            _reportController.state.status == GameReportStatus.cancelled)) {
      _scheduleAnalyze();
    }
  }

  String? _unavailableMessage({
    required bool finished,
    required bool hasMoves,
  }) {
    if (!hasMoves) return 'Game analysis needs at least one move';
    if (!finished) return 'Game analysis starts when the game ends';
    return null;
  }

  void reveal() {
    if (!mounted) return;
    final fingerprint = state.fingerprint;
    if (fingerprint == null || fingerprint == state.revealedFingerprint) {
      return;
    }
    _emit(state.copyWith(revealedFingerprint: fingerprint));
  }

  Future<void> retry() async {
    if (!mounted || !_active || !state.isEligible) return;
    _autoStartTimer?.cancel();
    _reportController.invalidate();
    await _analyze();
  }

  void _scheduleAnalyze() {
    // configure() is invoked from the notation build lifecycle. Keep the first
    // scheduled start so unrelated rebuilds cannot postpone analysis forever.
    if (_autoStartTimer?.isActive ?? false) return;
    _autoStartTimer = Timer(_autoStartDelay, () {
      _autoStartTimer = null;
      if (!mounted || !_active || !state.isEligible) return;
      unawaited(_analyze());
    });
  }

  Future<void> _analyze() async {
    final game = _game;
    if (!mounted || game == null || !_active || !state.isEligible) return;
    await _reportController.analyze(
      game,
      whiteRating: _whiteRating,
      blackRating: _blackRating,
    );
  }

  void _onReportChanged() {
    if (!mounted) return;
    var next = state.copyWith(reportState: _reportController.state);
    // Persist reveal when the report is ready so notation and sheet share the
    // same fingerprint latch (classificationsRevealed also treats completed
    // reports as revealed even if this side-effect races).
    if (_reportController.state.status == GameReportStatus.completed &&
        next.fingerprint != null &&
        next.fingerprint != next.revealedFingerprint) {
      next = next.copyWith(revealedFingerprint: next.fingerprint);
    }
    _emit(next);
  }

  @override
  void dispose() {
    _autoStartTimer?.cancel();
    _reportController.removeListener(_onReportChanged);
    _reportController.dispose();
    _sheetListenable.dispose();
    super.dispose();
  }
}

/// Per-board-page game review. [StateNotifierProvider] so UI watches immutable
/// [MobileGameReviewState] and rebuilds when report status/progress changes —
/// including when the report completes and notation should attach icons.
final mobileGameReviewProvider = StateNotifierProvider.autoDispose
    .family<
      MobileGameReviewController,
      MobileGameReviewState,
      ChessBoardProviderParams
    >((ref, params) => MobileGameReviewController());

/// Private listenable so the modal sheet can rebuild without being a Riverpod
/// consumer, while board/notation use [mobileGameReviewProvider] properly.
class _ReviewSheetListenable extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Whether notation/board should attach classification icons from the review
/// report for the board game identified by [boardGameFingerprint].
///
/// A **completed** report for this game is enough — the user does not need to
/// open the Game Analysis sheet (or any other reveal gesture). Sheet open still
/// sets [MobileGameReviewState.revealedFingerprint] for other UI, but icons
/// must light up as soon as the report finishes.
///
/// Pure helper so unit tests can drive the same gate the board screen uses.
bool shouldShowReportClassificationsOnBoard({
  required MobileGameReviewState reviewState,
  required String boardGameFingerprint,
}) {
  final report = reviewState.reportState.report;
  if (report == null) return false;
  if (reviewState.reportState.status != GameReportStatus.completed) {
    return false;
  }
  // Accept a match on the live board game or the review controller's
  // configured fingerprint so a navigator rebuild cannot drop icons.
  if (report.fingerprint == boardGameFingerprint) return true;
  final stateFp = reviewState.fingerprint;
  return stateFp != null && report.fingerprint == stateFp;
}

/// Zero-based mainline move index → classification for notation chips.
///
/// Uses mainline order (index in [GameAnalysisReport.moves]) so notation tokens
/// keyed by `node.ply - startingPly` / pointer[0] align even if a move's
/// 1-based [GameReportMove.ply] were ever off-by-one.
Map<int, GameMoveClassification> gameReportClassificationByMoveIndex(
  GameAnalysisReport report,
) {
  final out = <int, GameMoveClassification>{};
  for (var i = 0; i < report.moves.length; i++) {
    final classification = report.moves[i].classification;
    if (classification == null) continue;
    out[i] = classification;
  }
  return out;
}

/// Report-derived classification map ready for notation/board attach, or empty
/// when the gate fails. Drives the same inputs `_MovesDisplay` uses without
/// requiring the review sheet to call [MobileGameReviewController.reveal].
Map<int, GameMoveClassification> reportClassificationsForNotationAttach({
  required MobileGameReviewState reviewState,
  required String boardGameFingerprint,
}) {
  if (!shouldShowReportClassificationsOnBoard(
    reviewState: reviewState,
    boardGameFingerprint: boardGameFingerprint,
  )) {
    return const <int, GameMoveClassification>{};
  }
  final report = reviewState.reportState.report;
  if (report == null) return const <int, GameMoveClassification>{};
  return gameReportClassificationByMoveIndex(report);
}
