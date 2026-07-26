import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game_analysis_quota_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
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
/// Free users: on-demand only, 1 new report per UTC day (server RPC).
/// Premium users: unlimited and auto-start when the board is active.
class MobileGameReviewController
    extends StateNotifier<MobileGameReviewState> {
  static const Duration defaultAutoStartDelay = Duration(seconds: 2);

  MobileGameReviewController({
    GameAnalysisReportController? reportController,
    Duration autoStartDelay = defaultAutoStartDelay,
    bool Function()? isPremium,
    Future<GameAnalysisClaimResult> Function(String fingerprint)? claimQuota,
    GameReportBookLookup? bookLookup,
  }) : _reportController =
           reportController ??
           GameAnalysisReportController(bookLookup: bookLookup),
       _autoStartDelay = autoStartDelay,
       _isPremium = isPremium ?? (() => false),
       _claimQuota =
           claimQuota ??
           ((_) async => const GameAnalysisClaimResult(
             allowed: false,
             reason: 'unconfigured',
             isPremium: false,
           )),
       super(const MobileGameReviewState()) {
    _reportController.addListener(_onReportChanged);
  }

  final GameAnalysisReportController _reportController;
  final bool Function() _isPremium;
  final Future<GameAnalysisClaimResult> Function(String fingerprint) _claimQuota;

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
      // Previous generations: session memory, then durable local store.
      // Cached reports do not consume the free daily quota.
      if (state.isEligible) {
        if (!_reportController.loadCachedReport(fingerprint)) {
          unawaited(_reportController.loadPersistedReport(fingerprint));
        }
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
    _maybeAutoStart();
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
    _maybeAutoStart();
  }

  void _maybeAutoStart() {
    // Free users are on-demand only. Premium may auto-start when idle.
    if (!_isPremium()) return;
    if (!state.isEligible) return;
    if (_reportController.state.status != GameReportStatus.idle &&
        _reportController.state.status != GameReportStatus.cancelled) {
      return;
    }
    _scheduleAnalyze();
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

  /// Explicit user-started analysis. Handles auth + daily quota + paywall.
  Future<void> requestAnalysis(BuildContext context) async {
    if (!mounted || !state.isEligible) return;
    _autoStartTimer?.cancel();
    final game = _game;
    if (game == null) return;
    final fingerprint = gameReportFingerprint(game);
    // Capture navigator context before any await so lints stay clean.
    final hostContext = context;

    // Cached / already-completed reports never spend a free slot.
    if (_reportController.loadCachedReport(fingerprint)) return;
    if (await _reportController.loadPersistedReport(fingerprint)) return;
    if (!mounted || !hostContext.mounted) return;

    final claim = await _claimWithUi(hostContext, fingerprint);
    if (!mounted || !claim) return;

    await _reportController.analyze(
      game,
      whiteRating: _whiteRating,
      blackRating: _blackRating,
    );
  }

  /// Sheet "Retry" / "Analyze Game" — same gated path as the notation button.
  Future<void> retry([BuildContext? context]) async {
    if (!mounted || !_active || !state.isEligible) return;
    _autoStartTimer?.cancel();
    if (context != null) {
      await requestAnalysis(context);
      return;
    }
    // No context (tests / auto path): only run when premium or cache exists.
    final game = _game;
    if (game == null) return;
    final fingerprint = gameReportFingerprint(game);
    if (_reportController.loadCachedReport(fingerprint)) return;
    if (await _reportController.loadPersistedReport(fingerprint)) return;
    if (!_isPremium()) return;
    final claim = await _claimQuota(fingerprint);
    if (!claim.allowed || !mounted) return;
    await _reportController.analyze(
      game,
      whiteRating: _whiteRating,
      blackRating: _blackRating,
    );
  }

  Future<bool> _claimWithUi(BuildContext hostContext, String fingerprint) async {
    try {
      final result = await _claimQuota(fingerprint);
      if (result.allowed) return true;
      if (!hostContext.mounted) return false;

      if (result.needsAuth) {
        final authenticated = await requireFullAuthGuard(hostContext);
        if (!authenticated || !hostContext.mounted) return false;
        final retry = await _claimQuota(fingerprint);
        if (retry.allowed) return true;
        if (!hostContext.mounted) return false;
        if (retry.dailyLimitReached) {
          final subscribed = await showPremiumPaywallSheet(
            context: hostContext,
          );
          if (subscribed && hostContext.mounted) {
            final afterPay = await _claimQuota(fingerprint);
            return afterPay.allowed;
          }
        }
        return false;
      }

      if (result.dailyLimitReached) {
        final subscribed = await showPremiumPaywallSheet(context: hostContext);
        if (subscribed && hostContext.mounted) {
          final afterPay = await _claimQuota(fingerprint);
          return afterPay.allowed;
        }
        return false;
      }

      return false;
    } catch (e, st) {
      debugPrint('Game analysis quota claim failed: $e\n$st');
      if (!hostContext.mounted) return false;
      return showPremiumPaywallSheet(context: hostContext);
    }
  }

  void _scheduleAnalyze() {
    if (_autoStartTimer?.isActive ?? false) return;
    _autoStartTimer = Timer(_autoStartDelay, () {
      _autoStartTimer = null;
      if (!mounted || !_active || !state.isEligible) return;
      if (!_isPremium()) return;
      unawaited(_analyzePremiumAuto());
    });
  }

  Future<void> _analyzePremiumAuto() async {
    final game = _game;
    if (!mounted || game == null || !_active || !state.isEligible) return;
    final fingerprint = gameReportFingerprint(game);
    if (_reportController.loadCachedReport(fingerprint)) return;
    if (await _reportController.loadPersistedReport(fingerprint)) return;
    if (!mounted) return;
    // Server still authorizes; premium returns allowed without spending a slot.
    final claim = await _claimQuota(fingerprint);
    if (!claim.allowed || !mounted) return;
    await _reportController.analyze(
      game,
      whiteRating: _whiteRating,
      blackRating: _blackRating,
    );
  }

  void _onReportChanged() {
    if (!mounted) return;
    var next = state.copyWith(reportState: _reportController.state);
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
    >((ref, params) {
      return MobileGameReviewController(
        isPremium: () => ref.read(subscriptionProvider).isSubscribed,
        claimQuota:
            (fingerprint) =>
                ref.read(gameAnalysisQuotaRepositoryProvider).claim(fingerprint),
        bookLookup: _gamebaseBookLookup(ref),
      );
    });

/// Opening-tree lookup backed by the game database.
///
/// Returns null without a key so book detection stays off rather than throwing
/// once per opening move on every report.
GameReportBookLookup? _gamebaseBookLookup(Ref ref) {
  final repository = ref.read(gamebaseRepositoryProvider);
  if (!repository.hasApiKey) return null;
  return (fen, uci, path) async {
    // Same request the board's opening-explorer panel makes: handing over the
    // move line is what lets the backend answer past its indexed opening
    // window, where a fen-only query returns an empty tree.
    final response = await repository.getMoveAggregates(fen: fen, moves: path);
    for (final aggregate in response.data.moves) {
      if (gamebaseAggregateMatchesMove(aggregate.uci, uci)) {
        return aggregate.total;
      }
    }
    // The position is known but this continuation is not in it — a real answer
    // of "no games", distinct from a failed lookup.
    return 0;
  };
}

/// Whether a gamebase aggregate row and a board move are the same move.
///
/// They disagree on castling: dartchess gives the board `e1h1` while the
/// backend answers `e1g1`. Compared raw, every castle read as a move the
/// database had never seen — which, under the old walk, ended book detection at
/// the first time either side castled.
///
/// Pure helper so a unit test can hold the two spellings together.
bool gamebaseAggregateMatchesMove(String aggregateUci, String moveUci) =>
    aggregateUci == moveUci ||
    GamebaseRepository.alternateCastlingUci(moveUci) == aggregateUci;

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
