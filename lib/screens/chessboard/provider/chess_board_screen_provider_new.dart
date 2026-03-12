import 'dart:async';
import 'dart:math' as math;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator_state_manager.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int _minPersistDepth = 20;
const int _minPersistFullMoves = 8;
const Duration _evalWatchdogInterval = Duration(milliseconds: 1000);
const Duration _evalWatchdogMinActiveRuntime = Duration(seconds: 4);
const Duration _cascadeEvalSoftTimeout = Duration(milliseconds: 60);

bool _shouldPersistCloudEval(CloudEval eval) {
  return eval.meetsPersistenceThreshold(
    minDepth: _minPersistDepth,
    minFullMoves: _minPersistFullMoves,
  );
}

// REMOVED: Hardcoded limit - now we use all PVs that were requested
// const int _kMaxPrincipalVariations = 3;

enum ChessboardView { favScorecard, tour, countryman, playerProfile, forYou }

final chessboardViewFromProviderNew = StateProvider<ChessboardView>((ref) {
  return ChessboardView.tour;
});

/// All games currently loaded in the board screen.
/// Used by the player name tap → score card flow to pass full event context
/// (especially for TWIC where no broadcast model is available).
final chessBoardAllGamesProvider = StateProvider<List<GamesTourModel>>(
  (ref) => const [],
);

// Global provider to track the currently visible page index
// This prevents off-screen games from playing audio or triggering unnecessary updates
final currentlyVisiblePageIndexProvider = StateProvider<int>((ref) {
  return 0;
});

/// Global provider to track last seen move count per game
/// This is used to determine if there are unseen moves when new moves arrive
final lastSeenMoveCountProvider = StateProvider<Map<String, int>>((ref) {
  return {};
});

void _releaseLog(String message) {
  if (kReleaseMode) {
    // Ensure logs show up when running release builds from IDE.
    // ignore: avoid_print
    print(message);
  } else {
    debugPrint(message);
  }
}

class _BranchHistory {
  final List<String> sanMoves;
  final List<Move?> moveObjects;
  final List<Position> positions;

  const _BranchHistory({
    required this.sanMoves,
    required this.moveObjects,
    required this.positions,
  });
}

class _NavigationRequest {
  final int delta;
  final Completer<void> completer;

  _NavigationRequest(this.delta) : completer = Completer<void>();
}

class ChessBoardScreenNotifierNew
    extends StateNotifier<AsyncValue<ChessBoardStateNew>> {
  ChessBoardScreenNotifierNew(
    this.ref, {
    required this.game,
    required this.index,
    this.savedAnalysisData,
    this.startAtLastMove = false,
  }) : super(const AsyncValue.loading()) {
    _stockfishOwnerId = StockfishSingleton.generateOwnerId(game.gameId, index);
    _initializeState();
    _setupPgnStreamListener();
  }

  final Ref ref;
  GamesTourModel game;
  final int index;

  /// Unique owner ID for Stockfish job isolation.
  /// Allows this provider to cancel only its own jobs without affecting others.
  late final String _stockfishOwnerId;

  /// Optional saved analysis data to restore full state.
  /// Mutable so it can be set after a first-time save from the save sheet.
  SavedAnalysisData? savedAnalysisData;
  final bool startAtLastMove;
  Timer? _longPressTimer;
  bool _hasParsedMoves = false;
  bool _isProcessingMove = false;
  bool _isLongPressing = false;
  bool _cancelEvaluation = false;
  bool _isNavigationProcessing = false;
  final List<_NavigationRequest> _navigationQueue = <_NavigationRequest>[];
  String? _pendingEvalFen;
  Timer? _evalWatchdogTimer;
  bool _resumeVariantAutoPlay = false;
  bool _isPlayingVariant = false;
  final Map<String, DateTime> _failedEvalTimestamps = {};
  int _evalRequestCounter = 0;
  int? _activeEvalRequestId;
  String? _activeEvalKey;
  DateTime? _activeEvalStartTime; // Track when active eval started
  int _consecutiveWatchdogTimeouts =
      0; // Track consecutive watchdog timeouts for force recovery
  ChessGame? _analysisGame;
  ChessGameNavigatorStateManager? _analysisStateManager;
  ProviderSubscription<ChessGameNavigatorState>? _navigatorSubscription;
  bool _isInitialLoad = true;
  ChessBoardStateNew? _pvPreviewSnapshot;
  Timer? _autoSaveTimer;
  /// Snapshot of the game tree at last auto-save for diff detection
  String? _lastAutoSavedGameJson;

  void _clearActiveEvalState() {
    _activeEvalKey = null;
    _activeEvalRequestId = null;
    _activeEvalStartTime = null;
  }

  void _initializeState() {
    // Start with an initial data state to ensure proper initialization
    // The loading flag is handled by isLoadingMoves
    // Load showEngineAnalysis from persisted settings
    final engineSettingsAsync = ref.read(engineSettingsProviderNew);
    final engineSettings = engineSettingsAsync.valueOrNull;
    final showEngineAnalysis = engineSettings?.showEngineAnalysis ?? true;

    // Check if we're restoring from saved analysis
    final isBoardFlipped = savedAnalysisData?.isBoardFlipped ?? false;
    final variationComments = savedAnalysisData?.variationComments ?? const {};

    debugPrint(
      '🎯 ChessBoard[$index]: Initializing with showEngineAnalysis=$showEngineAnalysis (from settings: ${engineSettings?.showEngineAnalysis})',
    );

    if (savedAnalysisData != null) {
      debugPrint(
        '🎯 ChessBoard[$index]: Restoring from saved analysis ${savedAnalysisData!.analysisId}',
      );
      debugPrint(
        '🎯 ChessBoard[$index]: Board flipped=$isBoardFlipped, comments=${variationComments.length}',
      );
    }

    // For live games, seed the board with the current live FEN so it renders
    // the actual position immediately instead of flashing Chess.initial.
    final liveFenPosition = _tryParseLiveFenPlaceholder();

    state = AsyncValue.data(
      ChessBoardStateNew(
        game: game,
        pgnData: null,
        isLoadingMoves: true,
        fenData: game.fen,
        evaluation: null,
        isEvaluating: false,
        isAnalysisMode: true,
        showEngineAnalysis: showEngineAnalysis, // Load from settings
        showPrincipalVariations:
            showEngineAnalysis, // Keep PV visibility in sync with engine toggle
        isBoardFlipped: isBoardFlipped, // Restore from saved analysis
        variationComments: Map<String, String>.from(
          variationComments,
        ), // Restore comments
        position: liveFenPosition,
        analysisState: liveFenPosition != null
            ? AnalysisBoardState(position: liveFenPosition)
            : const AnalysisBoardState(),
      ),
    );
    parseMoves();

    // Listen for engine settings changes and clear cache to force re-evaluation
    ref.listen<AsyncValue<EngineSettings>>(engineSettingsProviderNew, (
      previous,
      next,
    ) {
      // Skip the initial fire during provider initialization to avoid
      // "Providers are not allowed to modify other providers during their initialization"
      if (previous == null) return;

      final prevValue = previous.value;
      final nextValue = next.value;

      if (prevValue != nextValue && nextValue != null) {
        _releaseLog('');
        _releaseLog('🔄 ═══ ENGINE SETTINGS CHANGED ═══');
        _releaseLog('   Previous:');
        _releaseLog(
          '     - Search Time: ${prevValue?.searchTimeLabel() ?? "null"}',
        );
        _releaseLog(
          '     - PV Setting: ${prevValue?.principalVariationLabel() ?? "null"}',
        );
        _releaseLog(
          '     - Engine Visibility: ${prevValue?.showEngineAnalysis ?? "null"}',
        );
        _releaseLog('   New:');
        _releaseLog('     - Search Time: ${nextValue.searchTimeLabel()}');
        _releaseLog(
          '     - PV Setting: ${nextValue.principalVariationLabel()}',
        );
        _releaseLog(
          '     - Engine Visibility: ${nextValue.showEngineAnalysis}',
        );
        _releaseLog(
          '     - Search Duration: ${nextValue.searchDurationFor(EngineComponent.evaluationGauge)?.inSeconds}s',
        );
        _releaseLog(
          '     - Max Depth: ${nextValue.maxDepthFor(EngineComponent.evaluationGauge)}',
        );
        _releaseLog('');

        // Sync engine analysis visibility from settings
        final currentState = state.valueOrNull;
        if (currentState != null &&
            currentState.showEngineAnalysis != nextValue.showEngineAnalysis) {
          _releaseLog(
            '   🔄 Syncing engine visibility: ${currentState.showEngineAnalysis} → ${nextValue.showEngineAnalysis}',
          );
          state = AsyncValue.data(
            currentState.copyWith(
              showEngineAnalysis: nextValue.showEngineAnalysis,
              showPrincipalVariations: nextValue.showEngineAnalysis,
            ),
          );
        }

        // Clear state's PVs immediately to show loading state
        if (currentState != null &&
            currentState.principalVariations.isNotEmpty) {
          _releaseLog(
            '   🗑️  Clearing ${currentState.principalVariations.length} cached PVs from state',
          );
          state = AsyncValue.data(
            currentState.copyWith(
              principalVariations: const [],
              principalVariationsBaseFen: null,
              selectedVariantIndex: null,
              variantBaseFen: null,
              variantMovePointer: const [],
            ),
          );
        }

        // Check if PV setting specifically changed (not just search time)
        final pvSettingChanged =
            prevValue?.principalVariationIndex !=
            nextValue.principalVariationIndex;

        if (pvSettingChanged) {
          // ALWAYS trigger re-evaluation when PV setting changes
          // This ensures new PVs are fetched even if user navigates away and back
          _releaseLog(
            '   → Forcing re-evaluation with new PV setting=${nextValue.principalVariationLabel()} (was ${prevValue?.principalVariationLabel() ?? "null"})...',
          );
          _evaluatePosition(force: true);
          _releaseLog('   ✅ Re-evaluation triggered for PV setting change');
        } else {
          // For other settings (like search time), only re-evaluate if currently visible
          final currentVisiblePage = ref.read(
            currentlyVisiblePageIndexProvider,
          );
          if (index == currentVisiblePage) {
            _releaseLog('   → Forcing re-evaluation with new settings...');
            _evaluatePosition(force: true);
            _releaseLog('   ✅ Re-evaluation triggered');
          } else {
            _releaseLog(
              '   🚫 Skipping re-evaluation for non-visible game (page $index, visible: $currentVisiblePage)',
            );
          }
        }
      }
    }, fireImmediately: true);
  }

  String? _currentPositionFen() {
    final currentState = state.value;
    if (currentState == null) {
      return null;
    }
    final position =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position;
    return position?.fen;
  }

  int _currentMultiPvSetting() {
    final engineSettingsAsync = ref.read(engineSettingsProviderNew);
    final engineSettings = engineSettingsAsync.value ?? const EngineSettings();
    return engineSettings.multiPvForStockfish();
  }

  void _registerPendingEvaluation(String fen) {
    final normalizedFen = _normalizeFen(fen);
    _pendingEvalFen = normalizedFen;
    _scheduleEvalWatchdog(normalizedFen);
  }

  void _scheduleEvalWatchdog(String normalizedFen) {
    _evalWatchdogTimer?.cancel();
    _evalWatchdogTimer = Timer(
      _evalWatchdogInterval,
      () => _handleEvalWatchdogTimeout(normalizedFen),
    );
  }

  bool _hasRecentDepthProgressForFen(String targetFen) {
    final depthMap = ref.read(engineDepthTrackerProvider);
    final now = DateTime.now();
    final maxAge = Duration(
      milliseconds: _evalWatchdogInterval.inMilliseconds * 2,
    );

    for (final component in const <EngineComponent>[
      EngineComponent.evaluationGauge,
      EngineComponent.principalVariation,
    ]) {
      final progress = depthMap[component];
      if (progress == null) continue;
      if (_normalizeFen(progress.fenFragment) != targetFen) continue;
      if (now.difference(progress.timestamp) <= maxAge) {
        return true;
      }
    }

    return false;
  }

  void _handleEvalWatchdogTimeout(String targetFen) {
    if (!mounted || _pendingEvalFen != targetFen) {
      return;
    }

    final visibleIndex = ref.read(currentlyVisiblePageIndexProvider);
    if (visibleIndex != index || _cancelEvaluation || _isLongPressing) {
      _scheduleEvalWatchdog(targetFen);
      return;
    }

    final currentFen = _currentPositionFen();
    if (currentFen == null) {
      _pendingEvalFen = null;
      _cancelEvalWatchdog();
      return;
    }
    final normalizedCurrent = _normalizeFen(currentFen);
    if (normalizedCurrent != targetFen) {
      return;
    }

    final isEvaluating = state.value?.isEvaluating ?? false;
    if (!isEvaluating) {
      _pendingEvalFen = null;
      _cancelEvalWatchdog();
      return;
    }

    final int multiPv = _currentMultiPvSetting();
    final targetKey = _fenCacheKey(targetFen, multiPV: multiPv);
    final bool hasActiveEval =
        _activeEvalRequestId != null && _activeEvalKey == targetKey;

    // Check how long the evaluation has been running
    final evalDuration =
        _activeEvalStartTime != null
            ? DateTime.now().difference(_activeEvalStartTime!)
            : Duration.zero;

    final stateSnapshot = state.value;
    final hasTargetPvProgress =
        stateSnapshot != null &&
        stateSnapshot.principalVariationsBaseFen != null &&
        _normalizeFen(stateSnapshot.principalVariationsBaseFen!) == targetFen &&
        stateSnapshot.principalVariations.isNotEmpty;
    final hasRecentDepthProgress = _hasRecentDepthProgressForFen(targetFen);

    // If Stockfish is still producing data for this FEN, keep monitoring without forcing a restart.
    if (hasActiveEval && (hasTargetPvProgress || hasRecentDepthProgress)) {
      _scheduleEvalWatchdog(targetFen);
      return;
    }

    // Give deep searches time to breathe before declaring a stall.
    if (hasActiveEval && evalDuration < _evalWatchdogMinActiveRuntime) {
      _scheduleEvalWatchdog(targetFen);
      return;
    }

    _consecutiveWatchdogTimeouts++;
    _releaseLog(
      '⚠️ EVAL WATCHDOG: Stalled evaluation for $targetFen (duration: ${evalDuration.inSeconds}s, consecutive: $_consecutiveWatchdogTimeouts), forcing restart',
    );
    _pendingEvalFen = null;
    _cancelEvalWatchdog();
    _cancelEvaluation = false;
    _clearActiveEvalState();

    // Cancel this provider's stuck Stockfish evaluations
    unawaited(
      StockfishSingleton().cancelEvaluationsForOwner(_stockfishOwnerId),
    );

    // Clear the evaluating flag to prevent UI from being stuck
    if (stateSnapshot != null && stateSnapshot.isEvaluating) {
      state = AsyncValue.data(stateSnapshot.copyWith(isEvaluating: false));
    }

    // If we've had too many consecutive watchdog timeouts, give up to prevent infinite loop
    final stockfish = StockfishSingleton();

    if (_consecutiveWatchdogTimeouts >= 6) {
      _releaseLog(
        '🛑 EVAL WATCHDOG: Giving up after $_consecutiveWatchdogTimeouts timeouts, final recovery attempt',
      );
      _consecutiveWatchdogTimeouts = 0;
      stockfish.forceRecovery().then((_) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) _evaluatePosition(force: true);
          });
        }
      });
      return;
    }

    // After 3+ timeouts, force recovery regardless of engine health state
    // (engine can appear "ready" while actually unresponsive)
    if (_consecutiveWatchdogTimeouts >= 3) {
      _releaseLog(
        '🔧 EVAL WATCHDOG: Forcing recovery after $_consecutiveWatchdogTimeouts timeouts (state: ${stockfish.engineStateDebug})',
      );
      stockfish.forceRecovery().then((_) {
        if (mounted) {
          _evaluatePosition(force: true);
        }
      });
      return;
    }

    // Simple delayed retry for early timeouts
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _evaluatePosition(force: true);
      }
    });
  }

  void _resolvePendingEvaluation(String fen) {
    if (_pendingEvalFen == null) {
      return;
    }
    final normalizedFen = _normalizeFen(fen);
    if (_pendingEvalFen == normalizedFen) {
      _pendingEvalFen = null;
      _cancelEvalWatchdog();
      // Reset consecutive watchdog timeouts on successful evaluation
      _consecutiveWatchdogTimeouts = 0;
    }
  }

  void _cancelEvalWatchdog({bool resetPending = false}) {
    _evalWatchdogTimer?.cancel();
    _evalWatchdogTimer = null;
    if (resetPending) {
      _pendingEvalFen = null;
    }
  }

  /// Get evaluation with consistent perspective for evaluation bar display
  /// BULLETPROOF evaluation perspective handler
  /// This method GUARANTEES that ALL evaluations are in WHITE'S PERSPECTIVE
  ///
  /// The cascade provider (current_eval_provider.dart) already converts
  /// Stockfish evaluations to white's perspective before caching.
  /// Lichess API returns evaluations in white's perspective by default.
  ///
  /// CRITICAL CONTRACT:
  /// - Input: evaluation from engines (Stockfish, Lichess, etc.)
  ///   Most engines report scores from the SIDE TO MOVE perspective.
  /// - Output: MUST be normalized to WHITE'S perspective.
  /// - Positive (+) = White advantage, regardless of side to move
  /// - Negative (-) = Black advantage
  double _getConsistentEvaluation(double evaluation, String fen) {
    final parts = fen.split(' ');
    final isWhiteToMove = parts.length > 1 ? parts[1] == 'w' : true;
    final normalizedEval = isWhiteToMove ? evaluation : -evaluation;

    // VALIDATION: Extreme values should only occur in mate scenarios
    if (normalizedEval.abs() > 100.0 && normalizedEval.abs() < 99999) {
      // TEMPO-01-COMMENT
      // _releaseLog(
      //   '⚠️ EVAL WARNING: Unusual evaluation value $normalizedEval for FEN: $fen',
      // );
    }

    return normalizedEval;
  }

  int? _getConsistentMate(int? mate, String fen) {
    if (mate == null || mate == 0) return mate;
    final parts = fen.split(' ');
    final isWhiteToMove = parts.length > 1 ? parts[1] == 'w' : true;
    return isWhiteToMove ? mate : -mate;
  }

  String _fenCacheKey(String fen, {int? multiPV}) {
    final parts = fen.split(' ');
    final baseFen =
        parts.length < 4
            ? fen
            : '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';

    // Include multiPV count in cache key to prevent wrong PV count being returned
    // e.g., cached 3-PV result shouldn't be returned when user wants 5 PVs
    if (multiPV != null && multiPV > 0) {
      return '${baseFen}_pv$multiPV';
    }
    return baseFen;
  }

  void _updateLastSeenMoveCount(int moveCount) {
    Future.microtask(() {
      if (!mounted) return;
      final current = ref.read(lastSeenMoveCountProvider);
      ref.read(lastSeenMoveCountProvider.notifier).state = {
        ...current,
        game.gameId: moveCount,
      };
    });
  }

  void _setupPgnStreamListener() {
    // Only listen to game updates stream if the game is ongoing
    _releaseLog(
      '🔧 STREAM SETUP: game ${game.gameId}, index: $index, status: ${game.gameStatus}',
    );

    if (game.gameStatus.isOngoing) {
      _releaseLog('✅ LISTENER ACTIVE for game ${game.gameId}');
      // CONSOLIDATED: One stream for ALL game data (PGN, clocks, status, etc.)
      ref.listen(gameUpdatesStreamProvider(game.gameId), (previous, next) {
        _releaseLog('📡 STREAM EVENT for game ${game.gameId}');

        next.whenData((gameData) {
          if (gameData == null) return;

          _releaseLog(
            '📦 DATA: game ${game.gameId}, white_clock=${gameData['last_clock_white']}, black_clock=${gameData['last_clock_black']}, pgn_length=${(gameData['pgn'] as String?)?.length ?? 0}',
          );

          final currentState = state.value;
          if (currentState == null) return;

          // Check if PGN has changed (new moves)
          final newPgn = gameData['pgn'] as String?;
          final pgnChanged = newPgn != null && newPgn != game.pgn;
          final streamStatus = gameData['status'] as String?;

          // Update game data with ALL stream values including PGN
          game = game.copyWith(
            pgn: newPgn ?? game.pgn,
            fen: gameData['fen'] as String? ?? game.fen,
            lastMove: gameData['last_move'] as String? ?? game.lastMove,
            lastMoveTime:
                gameData['last_move_time'] != null
                    ? DateTime.tryParse(gameData['last_move_time'] as String)
                    : game.lastMoveTime,
            whiteClockSeconds: (gameData['last_clock_white'] as num?)?.round(),
            blackClockSeconds: (gameData['last_clock_black'] as num?)?.round(),
            gameStatus:
                streamStatus != null
                    ? _parseGameStatus(streamStatus)
                    : game.gameStatus,
          );

          // CRITICAL: Update state immediately with new game object to show clock changes
          state = AsyncValue.data(currentState.copyWith(game: game));

          // Only reparse moves if PGN actually changed (new moves arrived)
          if (pgnChanged) {
            _releaseLog('🆕 NEW MOVES: Reparsing PGN for game ${game.gameId}');
            _hasParsedMoves = false;
            parseMoves(pgnOverride: newPgn);
          }
        });
      });
    }
  }

  static const String _defaultStartFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  String? _buildPgnFromSavedAnalysis() {
    final savedGame = savedAnalysisData?.chessGame;
    if (savedGame == null) return null;

    var pgn = exportGameToPgn(savedGame);
    final hasFenHeader = savedGame.metadata.keys.any(
      (key) => key.toLowerCase() == 'fen',
    );
    final needsFenHeader =
        savedGame.startingFen.isNotEmpty &&
        savedGame.startingFen != _defaultStartFen &&
        !hasFenHeader;

    if (needsFenHeader) {
      final sections = pgn.split('\n\n');
      if (sections.length >= 2) {
        final headers = sections.first;
        final body = sections.sublist(1).join('\n\n');
        pgn =
            '$headers\n[FEN "${savedGame.startingFen}"]\n[SetUp "1"]\n\n$body';
      } else {
        pgn = '[FEN "${savedGame.startingFen}"]\n[SetUp "1"]\n\n${pgn.trim()}';
      }
    }

    return pgn;
  }

  GameStatus _parseGameStatus(String status) {
    switch (status) {
      case '1-0':
        return GameStatus.whiteWins;
      case '0-1':
        return GameStatus.blackWins;
      case '1/2-1/2':
      case '½-½':
        return GameStatus.draw;
      case '*':
        return GameStatus.ongoing;
      default:
        return GameStatus.unknown;
    }
  }

  Future<void> parseMoves({String? pgnOverride}) async {
    // Don't reparse if already parsing or already parsed
    if (_hasParsedMoves) return;
    _hasParsedMoves = true;

    // Get current state or null if in loading state (first initialization)
    final currentState = state.value;

    try {
      String? pgn = pgnOverride ?? game.pgn;

      Future<String?> fetchRemotePgn({required bool requireMoves}) async {
        final expected = requireMoves ? 'moves' : 'PGN';
        String? fallback;

        // 1) Supabase: live/tournament games.
        try {
          final supabasePgn = await ref
              .read(gameRepositoryProvider)
              .getGamePgn(game.gameId);
          if (supabasePgn != null && supabasePgn.trim().isNotEmpty) {
            if (!requireMoves) {
              _releaseLog(
                '✅ PGN fetch: Supabase provided $expected for ${game.gameId}',
              );
              return supabasePgn;
            }

            fallback ??= supabasePgn;
            if (pgnHasMoves(supabasePgn)) {
              _releaseLog(
                '✅ PGN fetch: Supabase provided $expected for ${game.gameId}',
              );
              return supabasePgn;
            }
          }
        } on ApiException catch (e) {
          _releaseLog('⚠️ PGN lookup skipped for ${game.gameId}: $e');
        } catch (e) {
          _releaseLog('⚠️ PGN lookup failed for ${game.gameId}: $e');
        }

        // 2) Gamebase: library / global search games.
        try {
          final gamebaseRepo = ref.read(gamebaseRepositoryProvider);
          final gameWithPgn = await gamebaseRepo.getGameWithPgn(game.gameId);
          if (gameWithPgn == null) return fallback;

          // Prefer a PGN built from the structured `data` payload if available.
          // This yields consistent formatting and reliable movetext.
          final built = buildPgnFromGamebaseData(gameWithPgn.data);
          final raw = gameWithPgn.pgn;

          for (final candidate in [built, raw]) {
            final trimmed = candidate?.trim();
            if (trimmed == null || trimmed.isEmpty) continue;

            if (!requireMoves) {
              _releaseLog(
                '✅ PGN fetch: Gamebase provided $expected for ${game.gameId}',
              );
              return trimmed;
            }

            fallback ??= trimmed;
            if (pgnHasMoves(trimmed)) {
              _releaseLog(
                '✅ PGN fetch: Gamebase provided $expected for ${game.gameId}',
              );
              return trimmed;
            }
          }
        } catch (e) {
          _releaseLog('⚠️ Gamebase PGN lookup failed for ${game.gameId}: $e');
        }

        return fallback;
      }

      // Prefer locally saved analysis data to avoid remote lookups for archived games
      if ((pgn == null || pgn.isEmpty) && savedAnalysisData != null) {
        pgn = _buildPgnFromSavedAnalysis();
      }

      // If we have no PGN, fetch the best available one (even if it has no
      // moves) to avoid falling back to placeholder/sample PGNs.
      if (pgn == null || pgn.trim().isEmpty) {
        final fetched = await fetchRemotePgn(requireMoves: false);
        if (!mounted) return;
        if (fetched != null) {
          pgn = fetched;
          game = game.copyWith(pgn: pgn);
        }
      }

      if ((pgn == null || pgn.trim().isEmpty) &&
          (game.fen?.isNotEmpty ?? false)) {
        pgn = _buildFenFallbackPgn(game.fen!);
      }

      // Ensure PGN is not empty
      if (pgn == null || pgn.trim().isEmpty) {
        pgn = _getSamplePgnData();
      }

      var resolvedPgn = pgn;

      // Avoid expensive re-parse when nothing changed (e.g. clock-only updates)
      if (currentState != null && currentState.pgnData == resolvedPgn) {
        state = AsyncValue.data(
          currentState.copyWith(game: game, isLoadingMoves: false),
        );
        return;
      }

      game = game.copyWith(pgn: resolvedPgn);
      var hasAttemptedUpgrade = false;
      late PgnGame gameData;
      late Position startingPos;
      late List<Move> allMoves;
      late List<String> moveSans;
      Move? lastMove;
      late Position finalPos;

      while (true) {
        gameData = PgnGame.parsePgn(resolvedPgn);
        startingPos = PgnGame.startingPosition(gameData.headers);

        Position tempPos = startingPos;
        allMoves = [];
        moveSans = [];

        for (final node in gameData.moves.mainline()) {
          final move = tempPos.parseSan(node.san);
          if (move == null) break;
          allMoves.add(move);
          moveSans.add(node.san);
          tempPos = tempPos.play(move);
        }

        final lastMoveIndex = allMoves.length - 1;
        lastMove = null;
        finalPos = startingPos;
        for (int i = 0; i <= lastMoveIndex; i++) {
          lastMove = allMoves[i];
          finalPos = finalPos.play(allMoves[i]);
        }

        // Header-only PGNs (Gamebase previews) parse successfully but contain no
        // movetext. If that happens, try upgrading to a full PGN with moves and
        // re-parse once.
        if (allMoves.isNotEmpty || hasAttemptedUpgrade) {
          break;
        }

        hasAttemptedUpgrade = true;
        final upgraded = await fetchRemotePgn(requireMoves: true);
        if (!mounted) return;
        if (upgraded == null ||
            upgraded.trim().isEmpty ||
            upgraded == resolvedPgn) {
          break;
        }

        resolvedPgn = upgraded;
        game = game.copyWith(pgn: resolvedPgn);
      }

      var lastMoveIndex = allMoves.length - 1;
      final moveTimes = _parseMoveTimesFromPgn(resolvedPgn);

      final liveFen = game.fen?.trim();
      final liveUci = game.lastMove?.trim();
      if (liveFen != null &&
          liveFen.isNotEmpty &&
          liveUci != null &&
          liveUci.isNotEmpty) {
        final parsedFen = _normalizeFen(finalPos.fen);
        final targetFen = _normalizeFen(liveFen);
        if (parsedFen != targetFen) {
          try {
            final extraMove = Move.parse(liveUci);
            if (extraMove != null && finalPos.isLegal(extraMove)) {
              final sanResult = finalPos.makeSan(extraMove);
              final candidate = finalPos.play(extraMove);
              if (_normalizeFen(candidate.fen) == targetFen) {
                allMoves.add(extraMove);
                moveSans.add(sanResult.$2);
                moveTimes.add('');
                lastMove = extraMove;
                finalPos = candidate;
                lastMoveIndex = allMoves.length - 1;
              }
            }
          } catch (_) {
            // Ignore live move patch failures and fall back to PGN state.
          }
        }
      }

      // Only update state if still mounted
      if (!mounted) return;

      // Check if there are new unseen moves
      final lastSeenMoveCount =
          ref.read(lastSeenMoveCountProvider)[game.gameId] ?? 0;
      final currentMoveCount = moveSans.length;
      final hasNewMoves = currentMoveCount > lastSeenMoveCount;
      final hadMovesPreviously =
          currentState?.analysisState.allMoves.isNotEmpty ?? false;
      final hasMovesNow = moveSans.isNotEmpty;

      // Use instance-level initial load flag instead of global lastSeenMoveCount
      // This ensures we ALWAYS focus on latest move when entering the game screen
      final isFirstLoad = _isInitialLoad;
      final wasViewingLastMove =
          currentState != null &&
          currentState.analysisState.allMoves.isNotEmpty &&
          currentState.analysisState.currentMoveIndex ==
              currentState.analysisState.allMoves.length - 1;
      final shouldForceLatestPosition =
          isFirstLoad || (!hadMovesPreviously && hasMovesNow);
      final shouldMarkAsUnseen =
          hasNewMoves && !shouldForceLatestPosition && !wasViewingLastMove;

      // Determine which move index to display:
      // - On initial load: always show latest move
      // - If user was viewing last move: jump to new last move
      // - If user was viewing an earlier move AND it's not initial load: stay at current position (don't jump)
      final isPreviewActive = currentState?.isPvPreviewActive == true;

      final newMoveIndex =
          isPreviewActive
              ? (currentState?.analysisState.currentMoveIndex ?? lastMoveIndex)
              : shouldForceLatestPosition
              ? lastMoveIndex
              : (wasViewingLastMove
                  ? lastMoveIndex // Jump to new last move if user was already viewing last
                  : currentState?.analysisState.currentMoveIndex ??
                      lastMoveIndex); // Stay at current position otherwise

      // Calculate position for the move index we're displaying
      Position displayPosition = startingPos;
      Move? displayLastMove;
      if (newMoveIndex >= 0 && newMoveIndex < allMoves.length) {
        for (int i = 0; i <= newMoveIndex; i++) {
          displayLastMove = allMoves[i];
          displayPosition = displayPosition.play(allMoves[i]);
        }
      }

      // Create new state (either from scratch or copying existing state)
      final newState =
          currentState != null
              ? currentState.copyWith(
                position: finalPos, // Always track the actual final position
                startingPosition: startingPos,
                lastMove: lastMove, // Always track the actual last move
                allMoves: allMoves,
                moveSans: moveSans,
                currentMoveIndex: newMoveIndex, // Respects viewing position
                pgnData: resolvedPgn,
                isLoadingMoves: false,
                evaluation: null, // Reset evaluation to trigger new calculation
                isEvaluating: true, // Show loading indicator while evaluating
                analysisState: AnalysisBoardState(
                  startingPosition: startingPos,
                  currentMoveIndex: newMoveIndex,
                  position: displayPosition,
                  lastMove: displayLastMove,
                  moveSans: moveSans,
                  allMoves:
                      allMoves, // Must include all moves for proper navigation
                ),
                moveTimes: moveTimes,
                hasUnseenMoves:
                    isPreviewActive
                        ? currentState.hasUnseenMoves
                        : shouldMarkAsUnseen,
              )
              : ChessBoardStateNew(
                game: game,
                position: finalPos,
                startingPosition: startingPos,
                lastMove: lastMove,
                allMoves: allMoves,
                moveSans: moveSans,
                currentMoveIndex: newMoveIndex,
                pgnData: resolvedPgn,
                isLoadingMoves: false,
                evaluation: null,
                isEvaluating: true,
                isAnalysisMode: true,
                // Preserve engine visibility when building fresh state
                showEngineAnalysis:
                    currentState?.showEngineAnalysis ??
                    ref
                        .read(engineSettingsProviderNew)
                        .valueOrNull
                        ?.showEngineAnalysis ??
                    true,
                showPrincipalVariations:
                    currentState?.showPrincipalVariations ??
                    ref
                        .read(engineSettingsProviderNew)
                        .valueOrNull
                        ?.showEngineAnalysis ??
                    true,
                analysisState: AnalysisBoardState(
                  startingPosition: startingPos,
                  currentMoveIndex: newMoveIndex,
                  position: displayPosition,
                  lastMove: displayLastMove,
                  moveSans: moveSans,
                  allMoves: allMoves,
                ),
                moveTimes: moveTimes,
                hasUnseenMoves:
                    isPreviewActive
                        ? (currentState?.hasUnseenMoves ?? false)
                        : shouldMarkAsUnseen,
              );

      state = AsyncValue.data(newState);

      // Update last seen move count when we auto-sync to the latest move
      if (shouldForceLatestPosition) {
        _updateLastSeenMoveCount(currentMoveCount);
      }
      if (_isInitialLoad) {
        _isInitialLoad =
            false; // Mark initial load as complete after first parse
      }
      _pvPreviewSnapshot = null;

      if (_analysisGame == null) {
        await _initializeAnalysisBoard();
      } else if (_analysisNavigator != null) {
        final liveAnalysisGame = _createChessGameFromPgn(resolvedPgn);
        _analysisNavigator!.updateWithLatestGame(liveAnalysisGame);

        // CRITICAL: When user was viewing the last move and new moves arrived,
        // jump the navigator to the tail so the animation plays.
        // Without this, the navigator stays at the old position and the
        // listener sync would reset the state back to the old move.
        if (wasViewingLastMove && hasNewMoves) {
          _analysisNavigator!.goToTail();
        }

        unawaited(_persistAnalysisState());
      }

      // CRITICAL: Only trigger evaluation if this is the currently visible game
      // This prevents resource-intensive analysis from running for off-screen games in PageView
      final currentVisiblePage = ref.read(currentlyVisiblePageIndexProvider);
      if (index == currentVisiblePage) {
        // Force immediate evaluation on live game new moves — bypasses the
        // 120ms debounce so the engine starts searching the new position ASAP.
        _updateEvaluation(force: hasNewMoves);
      } else {
        _releaseLog(
          '🚫 PARSE: Skipping evaluation for non-visible game (page $index, visible: $currentVisiblePage)',
        );
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  List<String> _parseMoveTimesFromPgn(String pgn) {
    final List<String> times = [];

    try {
      final game = PgnGame.parsePgn(pgn);

      // Iterate through the mainline moves
      for (final nodeData in game.moves.mainline()) {
        String? timeString;

        // Check if this move has comments
        if (nodeData.comments != null) {
          // Extract time if it exists in any comment
          for (String comment in nodeData.comments!) {
            final timeMatch = RegExp(
              r'\[%clk (\d+:\d+:\d+)\]',
            ).firstMatch(comment);
            if (timeMatch != null) {
              timeString = timeMatch.group(1);
              break; // Found time, no need to check other comments for this move
            }
          }
        }

        // Add formatted time or default if no time found
        if (timeString != null) {
          times.add(_formatDisplayTime(timeString));
        } else {
          times.add('-:--:--'); // Default for moves without time
        }
      }
    } catch (e) {
      _releaseLog('Error parsing PGN: $e');
      // Fallback to regex method if dartchess parsing fails
      return _parseMoveTimesFromPgnFallback(pgn);
    }

    return times;
  }

  // Fallback method using the original regex approach
  List<String> _parseMoveTimesFromPgnFallback(String pgn) {
    final List<String> times = [];
    final regex = RegExp(r'\{ \[%clk (\d+:\d+:\d+)\] \}');
    final matches = regex.allMatches(pgn);

    for (final match in matches) {
      final timeString = match.group(1) ?? '0:00:00';
      times.add(_formatDisplayTime(timeString));
    }

    return times;
  }

  String _formatDisplayTime(String timeString) {
    // Convert "1:40:57" to display format
    final parts = timeString.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = parts[1];
      final seconds = parts[2];

      // If less than an hour, show MM:SS format
      if (hours == 0) {
        return '$minutes:$seconds';
      }
      // Otherwise show H:MM:SS format
      return '$hours:$minutes:$seconds';
    }
    return timeString;
  }

  /// Mark all moves as seen (clear the unseen indicator)
  void markMovesAsSeen() {
    final currentState = state.value;
    if (currentState == null) return;

    // Update the state to clear the unseen flag
    state = AsyncValue.data(currentState.copyWith(hasUnseenMoves: false));

    // Update the global provider with the current move count
    _updateLastSeenMoveCount(currentState.moveSans.length);
  }

  Future<void> goToMove(int moveIndex) async {
    // Analysis mode is always active, use analysis navigation
    await analysisModeGoToMove(moveIndex);
  }

  Future<void> analysisModeGoToMove(int moveIndex) async {
    var currentState = state.value;
    if (currentState == null) return;

    final clearedState = _clearVariantSelection(currentState);
    if (!identical(clearedState, currentState)) {
      state = AsyncValue.data(clearedState);
      currentState = clearedState;
    }

    if (_analysisGame != null) {
      if (moveIndex < 0) {
        _analysisNavigator?.goToMovePointerUnchecked(const []);
      } else {
        _analysisNavigator?.goToMovePointerUnchecked([moveIndex]);
      }

      // Sync state after navigation
      final updatedState = ref.read(chessGameNavigatorProvider(_analysisGame!));
      _syncAnalysisFromNavigator(updatedState);
      return;
    }

    if (_isProcessingMove) return;
    _isProcessingMove = true;
    try {
      if (currentState.isLoadingMoves) {
        return;
      }

      if (moveIndex < -1 ||
          moveIndex >= currentState.analysisState.allMoves.length) {
        return;
      }
      _cancelEvaluation = true;
      await StockfishSingleton().cancelEvaluationsForOwner(_stockfishOwnerId);
      _clearActiveEvalState();
      Position newPosition = currentState.analysisState.startingPosition!;
      Move? newLastMove;

      for (int i = 0; i <= moveIndex; i++) {
        newLastMove = currentState.analysisState.allMoves[i];
        newPosition = newPosition.play(currentState.analysisState.allMoves[i]);
      }

      // Check if navigating to the last move to clear unseen indicator
      final isNavigatingToLastMove =
          moveIndex == currentState.analysisState.allMoves.length - 1;

      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            position: newPosition,
            lastMove: newLastMove,
            currentMoveIndex: moveIndex,
            suggestionLines: const [],
          ),
          evaluation: null, // Reset evaluation for new position
          mate: null,
          isEvaluating: true, // Show loading indicator while evaluating
          principalVariations: const [],
          principalVariationsBaseFen: null,
          selectedVariantIndex: null,
          variantMovePointer: const [],
          variantBaseFen: null,
          variantBaseMovePointer: null,
          variantBaseLastMove: null,
          variantBaseMoveIndex: null,
          shapes: const ISet.empty(),
          // Clear unseen indicator if navigating to the last move
          hasUnseenMoves:
              isNavigatingToLastMove ? false : currentState.hasUnseenMoves,
        ),
      );

      // Update last seen move count if navigating to the last move
      if (isNavigatingToLastMove && currentState.hasUnseenMoves) {
        _updateLastSeenMoveCount(currentState.moveSans.length);
      }

      _cancelEvaluation = false;
      _updateEvaluation(force: true);
    } finally {
      _isProcessingMove = false;
    }
  }

  Future<void> normalModeGoToMove(int moveIndex) async {
    if (_isProcessingMove) return;
    _isProcessingMove = true;

    final currentState = state.value;
    try {
      if (currentState == null || currentState.isLoadingMoves) {
        return;
      }
      if (moveIndex < -1 || moveIndex >= currentState.allMoves.length) {
        return;
      }

      _cancelEvaluation = true;
      await StockfishSingleton().cancelEvaluationsForOwner(_stockfishOwnerId);
      _clearActiveEvalState();

      Position newPosition = currentState.startingPosition!;
      Move? newLastMove;

      for (int i = 0; i <= moveIndex; i++) {
        newLastMove = currentState.allMoves[i];
        newPosition = newPosition.play(currentState.allMoves[i]);
      }

      state = AsyncValue.data(
        currentState.copyWith(
          position: newPosition,
          lastMove: newLastMove,
          currentMoveIndex: moveIndex,
          evaluation: null, // Reset evaluation for new position
          mate: null,
          isEvaluating: true, // Show loading indicator while evaluating
          analysisState: currentState.analysisState.copyWith(
            suggestionLines: const [],
          ),
          principalVariations: const [],
          principalVariationsBaseFen: null,
          selectedVariantIndex: null,
          variantMovePointer: const [],
          variantBaseFen: null,
          variantBaseMovePointer: null,
          variantBaseLastMove: null,
          variantBaseMoveIndex: null,
          shapes: const ISet.empty(),
        ),
      );

      _cancelEvaluation = false;
      _updateEvaluation(force: true);
    } finally {
      _isProcessingMove = false;
    }
  }

  void evaluateCurrentPosition() {
    _updateEvaluation();
  }

  void goToMovePointer(ChessMovePointer pointer) {
    _exitPvPreviewIfActive();
    if (_analysisGame == null) return;
    _releaseLog('🎯 GO TO MOVE POINTER: Navigating to pointer=$pointer');
    final currentState = state.value;
    if (currentState != null) {
      _releaseLog(
        '🎯 GO TO MOVE POINTER: Current board pointer=${currentState.analysisState.movePointer}',
      );
      final cleared = _clearVariantSelection(currentState);
      if (!identical(cleared, currentState)) {
        state = AsyncValue.data(cleared);
      }
    }
    _analysisNavigator?.goToMovePointerUnchecked(pointer);

    // Manually sync state after navigation to ensure board updates immediately.
    // The ref.listen callback may not fire synchronously.
    final updatedState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    _syncAnalysisFromNavigator(updatedState);
  }

  ChessGameNavigatorState? navigatorStateSnapshot() {
    if (_analysisGame == null) return null;
    final snapshot = ref.read(chessGameNavigatorProvider(_analysisGame!));
    return ChessGameNavigatorState(
      game: snapshot.game,
      movePointer: List<Number>.of(snapshot.movePointer),
    );
  }

  Future<void> restoreNavigatorState(ChessGameNavigatorState snapshot) async {
    if (_analysisNavigator == null) return;
    _analysisNavigator!.replaceState(snapshot);
    await _persistAnalysisState();
  }

  Future<void> deleteVariationAtPointer(ChessMovePointer pointer) async {
    _exitPvPreviewIfActive();
    if (_analysisNavigator == null) return;
    final currentState = state.value;
    if (currentState == null) return;
    final cleared = _clearVariantSelection(currentState);
    if (!identical(cleared, currentState)) {
      state = AsyncValue.data(cleared);
    }
    _analysisNavigator!.deleteVariationAtPointer(pointer);
    HapticFeedback.heavyImpact();
    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    _updateEvaluation(force: true);
    await _persistAnalysisState();
  }

  Future<void> promoteVariationAtPointer(ChessMovePointer pointer) async {
    _exitPvPreviewIfActive();
    if (_analysisNavigator == null) return;
    final currentState = state.value;
    if (currentState == null) return;
    final cleared = _clearVariantSelection(currentState);
    if (!identical(cleared, currentState)) {
      state = AsyncValue.data(cleared);
    }
    _analysisNavigator!.promoteVariationToMainline(pointer);
    HapticFeedback.heavyImpact();
    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    _updateEvaluation(force: true);
    await _persistAnalysisState();
  }

  Future<void> insertNullMoveAfterCurrent() async {
    if (_isEditingBlockedByPreview(reason: 'insert null move')) {
      return;
    }
    _exitPvPreviewIfActive();
    if (_analysisNavigator == null) return;
    _analysisNavigator!.insertNullMoveAtPointer();
    HapticFeedback.mediumImpact();
    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    _updateEvaluation(force: true);
    await _persistAnalysisState();
  }

  Future<void> deleteContinuationFromPointer(ChessMovePointer pointer) async {
    _exitPvPreviewIfActive();
    if (_analysisNavigator == null) return;
    final currentState = state.value;
    if (currentState == null) return;
    final cleared = _clearVariantSelection(currentState);
    if (!identical(cleared, currentState)) {
      state = AsyncValue.data(cleared);
    }
    _analysisNavigator!.deleteContinuationAfterPointer(pointer);
    HapticFeedback.mediumImpact();
    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    _updateEvaluation(force: true);
    await _persistAnalysisState();
  }

  Future<void> insertNullMoveAfterPointer(ChessMovePointer pointer) async {
    _exitPvPreviewIfActive();
    if (_analysisNavigator == null) return;
    final currentState = state.value;
    if (currentState == null) return;
    final cleared = _clearVariantSelection(currentState);
    if (!identical(cleared, currentState)) {
      state = AsyncValue.data(cleared);
    }
    _analysisNavigator!.insertNullMoveAtPointer(pointer);
    HapticFeedback.mediumImpact();
    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    _updateEvaluation(force: true);
    await _persistAnalysisState();
  }

  Future<void> promoteBranchToMainVariant(ChessMovePointer pointer) async {
    if (_analysisNavigator == null) return;
    final currentState = state.value;
    if (currentState == null) return;

    final sourceGame =
        currentState.analysisState.game ?? _analysisNavigator!.state.game;
    final branchLine = _extractMainlineFromPointer(sourceGame, pointer);
    if (branchLine == null || branchLine.isEmpty) {
      _releaseLog(
        '🎯 PROMOTE BRANCH: Failed to extract branch for pointer $pointer',
      );
      return;
    }

    final newGame = sourceGame.copyWith(mainline: branchLine);
    final movePointer =
        branchLine.isEmpty ? const <Number>[] : <Number>[branchLine.length - 1];

    _analysisNavigator!.replaceState(
      ChessGameNavigatorState(game: newGame, movePointer: movePointer),
    );

    final newPgn = exportGameToPgn(newGame);
    final cleared = _clearVariantSelection(currentState);
    state = AsyncValue.data(
      cleared.copyWith(
        pgnData: newPgn,
        principalVariations: const [],
        selectedVariantIndex: null,
        variantMovePointer: const [],
        variantBaseFen: null,
      ),
    );

    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    await _persistAnalysisState();
    _updateEvaluation(force: true);
    HapticFeedback.heavyImpact();
    _releaseLog('🎯 PROMOTE BRANCH: Completed promotion for pointer $pointer');
  }

  Future<void> clearUserAnalysis() async {
    if (_isEditingBlockedByPreview(reason: 'clear analysis')) {
      return;
    }
    _exitPvPreviewIfActive();
    if (_analysisNavigator == null) return;
    final currentState = state.value;
    if (currentState == null) return;

    var basePgn = currentState.pgnData ?? game.pgn;
    if ((basePgn == null || basePgn.trim().isEmpty) &&
        (game.fen?.isNotEmpty ?? false)) {
      basePgn = _buildFenFallbackPgn(game.fen!);
    }
    if (basePgn == null || basePgn.trim().isEmpty) {
      return;
    }

    final baseGame = _createChessGameFromPgn(basePgn);
    _analysisNavigator!
      ..replaceState(
        ChessGameNavigatorState(game: baseGame, movePointer: const []),
      )
      ..goToTail();

    _analysisNavigator!.goToTail();

    // Clear all variation comments
    if (currentState.variationComments.isNotEmpty) {
      state = AsyncValue.data(
        currentState.copyWith(variationComments: const <String, String>{}),
      );
    }

    await _persistAnalysisState();
  }

  void playPrincipalVariationMove(AnalysisLine line) {
    final wasPreviewActive = state.value?.isPvPreviewActive == true;
    if (wasPreviewActive) {
      _exitPvPreviewIfActive();
    }
    if (_isEditingBlockedByPreview(reason: 'play PV move')) {
      return;
    }
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.principalVariations.indexOf(line);
    if (index == -1) return;

    _releaseLog(
      '🎯 PLAY PV MOVE: index=$index, currentSelected=${currentState.selectedVariantIndex}',
    );

    // If already on this variant, just play forward
    if (currentState.selectedVariantIndex == index) {
      _releaseLog('🎯 PLAY PV MOVE: Already selected, playing forward');
      playVariantMoveForward();
      return;
    }

    // Select variant first (this will update the arrows)
    _releaseLog('🎯 PLAY PV MOVE: Selecting new variant');
    selectVariant(index);

    // Then play the first move forward
    Future.microtask(() {
      if (mounted && state.value?.selectedVariantIndex == index) {
        playVariantMoveForward();
      }
    });
  }

  /// Inserts all PV moves into the game history.
  /// If at the end of the current line, appends moves to mainline/variation.
  /// If NOT at the end, creates a new variation with parentheses.
  void insertPvMoves(AnalysisLine line) {
    if (_isEditingBlockedByPreview(reason: 'insert PV moves')) {
      return;
    }
    _exitPvPreviewIfActive();
    final currentState = state.value;
    if (currentState == null || line.moves.isEmpty) return;

    final navigator = _analysisNavigator;
    if (navigator == null) {
      _releaseLog('🎯 INSERT PV MOVES: No navigator available');
      return;
    }

    _releaseLog(
      '🎯 INSERT PV MOVES: Inserting ${line.moves.length} moves (${line.sanMoves.join(" ")})',
    );

    // Use the navigator's new method to append PV moves
    navigator.appendMovesFromPv(moves: line.moves, sanMoves: line.sanMoves);

    // Sync state with navigator after insertion
    Future.microtask(() {
      if (mounted) {
        _syncAnalysisFromNavigator(navigator.state);
        _updateEvaluation();
      }
    });
  }

  void updateVariationComment({
    required String variationId,
    required String comment,
  }) {
    final currentState = state.value;
    if (currentState == null) {
      return;
    }
    final trimmed = comment.trim();
    final limited =
        trimmed.length > kVariationCommentMaxChars
            ? trimmed.substring(0, kVariationCommentMaxChars)
            : trimmed;
    final nextComments = Map<String, String>.from(
      currentState.variationComments,
    );

    final existing = nextComments[variationId];
    if (limited.isEmpty) {
      if (existing == null) {
        return;
      }
      nextComments.remove(variationId);
    } else {
      if (existing == limited) {
        return;
      }
      nextComments[variationId] = limited;
    }

    state = AsyncValue.data(
      currentState.copyWith(variationComments: nextComments),
    );
    _scheduleAutoSave();
  }

  void previewPrincipalVariationMoveAt(
    AnalysisLine line,
    int variantIndex,
    int targetMoveIndex,
  ) {
    final currentState = state.value;
    if (currentState == null) return;
    if (line.moves.isEmpty) return;

    final currentAnalysis = currentState.analysisState;
    final previewFenBase = currentAnalysis.position.fen
        .split(' ')
        .take(3)
        .join(' ');
    final pvBaseFen = currentState.principalVariationsBaseFen;
    if (pvBaseFen != null) {
      final pvFenBase = pvBaseFen.split(' ').take(3).join(' ');
      if (pvFenBase != previewFenBase) {
        _releaseLog(
          '🎯 PV PREVIEW: PV lines are stale for current position, forcing re-evaluation',
        );
        _updateEvaluation(force: true);
        return;
      }
    }

    final cappedIndex = targetMoveIndex.clamp(0, line.moves.length - 1);

    // If already in preview mode, use current preview state as base for nested preview
    // Otherwise, save current state as snapshot for first preview
    final ChessBoardStateNew baseState;
    if (currentState.isPvPreviewActive &&
        currentState.lockedPvMergedMoves != null) {
      // Nested preview: use current preview position as base
      baseState = currentState;
      _releaseLog(
        '🎯 PV PREVIEW: Creating nested preview from current preview state',
      );
    } else {
      // First preview: save original state to restore later
      _pvPreviewSnapshot ??= currentState.copyWith();
      baseState = _pvPreviewSnapshot ?? currentState;
      _releaseLog(
        '🎯 PV PREVIEW: Creating first preview, saving original state',
      );
    }
    final baseAnalysis = baseState.analysisState;

    var previewPosition = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(baseAnalysis.position.fen),
    );
    Move? lastMove;

    for (int i = 0; i <= cappedIndex; i++) {
      final move = line.moves[i];
      if (!previewPosition.isLegal(move)) {
        _releaseLog('🎯 PV PREVIEW: illegal move ${move.uci} at index $i');
        return;
      }
      previewPosition = previewPosition.play(move);
      lastMove = move;
    }

    final previewAnalysis = baseAnalysis.copyWith(
      position: previewPosition,
      lastMove: lastMove,
      validMoves: makeLegalMoves(previewPosition),
    );

    // Create locked PV line: merge PGN history with PV moves
    // CRITICAL: When in nested preview, use the preview card's merged history as base
    final List<String> pgnHistory;
    final List<Move?> baseMoveObjects;
    List<Position> basePositions = const <Position>[];
    if (currentState.isPvPreviewActive &&
        currentState.lockedPvMergedMoves != null) {
      // Nested preview: Use preview card's merged history as base
      pgnHistory = currentState.lockedPvMergedMoves!;
      baseMoveObjects =
          currentState.lockedPvMergedMoveObjects ??
          List<Move?>.of(baseAnalysis.combinedMoves);
      basePositions =
          currentState.lockedPvMergedPositions != null
              ? List<Position>.of(currentState.lockedPvMergedPositions!)
              : <Position>[];
      _releaseLog(
        '🎯 PV PREVIEW: Using preview card history as base (${pgnHistory.length} moves)',
      );
    } else {
      // Prefer navigator history to ensure we capture the exact line (including parent variations)
      final navigatorState = _analysisNavigator?.state;
      final ChessGame? sourceGame =
          navigatorState?.game ?? baseState.analysisState.game;
      final ChessMovePointer effectivePointer =
          navigatorState != null && navigatorState.movePointer.isNotEmpty
              ? navigatorState.movePointer
              : baseState.analysisState.movePointer;

      final historySnapshot =
          sourceGame == null
              ? null
              : _collectBranchHistory(sourceGame, effectivePointer);

      if (historySnapshot != null) {
        pgnHistory = List<String>.of(historySnapshot.sanMoves);
        baseMoveObjects = List<Move?>.of(historySnapshot.moveObjects);
        basePositions = List<Position>.of(historySnapshot.positions);
      } else {
        // Fallback: use analysis state's linear history
        final currentMoveIndex = baseAnalysis.currentMoveIndex;
        final allSans = currentState.analysisState.moveSans;
        final allMoves = currentState.analysisState.allMoves;
        final endIndex = currentMoveIndex + 1;
        pgnHistory =
            endIndex > 0 && endIndex <= allSans.length
                ? allSans.sublist(0, endIndex)
                : <String>[];
        final movesSlice =
            endIndex > 0 && endIndex <= allMoves.length
                ? allMoves.sublist(0, endIndex)
                : <Move>[];
        baseMoveObjects = List<Move?>.of(movesSlice);

        Position startingPos;
        if (baseAnalysis.startingPosition != null) {
          startingPos = baseAnalysis.startingPosition!;
        } else if (baseState.startingPosition != null) {
          startingPos = baseState.startingPosition!;
        } else if (baseState.position != null) {
          startingPos = baseState.position!;
        } else {
          startingPos = baseAnalysis.position;
        }
        basePositions = <Position>[startingPos];
        var cursor = startingPos;
        for (final move in baseMoveObjects) {
          if (move == null) {
            continue;
          }
          cursor = cursor.play(move);
          basePositions.add(cursor);
        }
      }
      final loggedPositions = basePositions;
      _releaseLog(
        '🎯 PV PREVIEW: Using history snapshot (${pgnHistory.length} moves, ${baseMoveObjects.length} objects, ${loggedPositions.length} positions)',
      );
    }
    final pvMoves = line.moves;
    final mergedMoves = [...pgnHistory, ...line.sanMoves];
    final combinedMoveObjects = [...baseMoveObjects, ...pvMoves];

    // Build merged position history (start + every move)
    // CRITICAL: When in nested preview, reuse existing positions to avoid recalculation
    final List<Position> mergedPositions;
    if (currentState.isPvPreviewActive &&
        currentState.lockedPvMergedPositions != null) {
      // Nested preview: Extend the existing preview positions with new PV moves
      final existingPositions = currentState.lockedPvMergedPositions!;
      var positionCursor = existingPositions.last;
      final newPositions = <Position>[];
      for (final move in pvMoves) {
        positionCursor = positionCursor.play(move);
        newPositions.add(positionCursor);
      }
      mergedPositions = [...existingPositions, ...newPositions];
      _releaseLog(
        '🎯 PV PREVIEW: Extended existing positions (${existingPositions.length} + ${newPositions.length} = ${mergedPositions.length})',
      );
    } else {
      List<Position> basePositionHistory;
      if (basePositions.isNotEmpty) {
        basePositionHistory = List<Position>.of(basePositions);
      } else {
        Position startingPos;
        if (baseAnalysis.startingPosition != null) {
          startingPos = baseAnalysis.startingPosition!;
        } else if (baseState.startingPosition != null) {
          startingPos = baseState.startingPosition!;
        } else if (baseState.position != null) {
          startingPos = baseState.position!;
        } else {
          startingPos = baseAnalysis.position;
        }
        basePositionHistory = <Position>[startingPos];
        var cursor = startingPos;
        for (final move in baseMoveObjects) {
          if (move == null) {
            continue;
          }
          cursor = cursor.play(move);
          basePositionHistory.add(cursor);
        }
      }

      var positionCursor =
          basePositionHistory.isNotEmpty
              ? basePositionHistory.last
              : baseAnalysis.position;
      final newPositions = <Position>[];
      for (final move in pvMoves) {
        positionCursor = positionCursor.play(move);
        newPositions.add(positionCursor);
      }
      mergedPositions = [...basePositionHistory, ...newPositions];
      _releaseLog(
        '🎯 PV PREVIEW: Built base positions (${basePositionHistory.length}) + PV moves (${newPositions.length}) = ${mergedPositions.length}',
      );
    }

    final baseMoveCount = baseMoveObjects.length;
    final navigationIndex = cappedIndex;

    _releaseLog(
      '🎯 PV PREVIEW: Locking PV line (PGN history: ${pgnHistory.length}, PV moves: ${line.sanMoves.length}, merged: ${mergedMoves.length})',
    );

    state = AsyncValue.data(
      currentState.copyWith(
        analysisState: previewAnalysis,
        isPvPreviewActive: true,
        pvPreviewVariantIndex: variantIndex,
        pvPreviewMoveIndex: cappedIndex,
        lockedPvLine: line,
        lockedPvMergedMoves: mergedMoves,
        lockedPvMergedMoveObjects: combinedMoveObjects,
        lockedPvMergedPositions: mergedPositions,
        lockedPvBaseMoveCount: baseMoveCount,
        lockedPvNavigationIndex: navigationIndex,
        isEvaluating: true,
        shapes: const ISet.empty(),
      ),
    );

    _navigateToLockedPvIndex(navigationIndex, force: true);
  }

  void clearPvPreview() {
    _exitPvPreviewIfActive();
  }

  _BranchHistory? _collectBranchHistory(
    ChessGame game,
    ChessMovePointer pointer,
  ) {
    final sanMoves = <String>[];
    final moveObjects = <Move?>[];
    final positions = <Position>[];

    var position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(game.startingFen),
    );
    positions.add(position);

    if (game.mainline.isEmpty) {
      return _BranchHistory(
        sanMoves: sanMoves,
        moveObjects: moveObjects,
        positions: positions,
      );
    }

    ChessLine? currentLine = game.mainline;
    var pointerIndex = 0;
    var lastIncludedIndex = -1;

    while (currentLine != null) {
      if (currentLine.isEmpty) {
        break;
      }

      final rawMoveIndex =
          pointerIndex < pointer.length
              ? pointer[pointerIndex].toInt()
              : currentLine.length - 1;
      if (rawMoveIndex < 0) {
        break;
      }
      final cappedMoveIndex = rawMoveIndex.clamp(0, currentLine.length - 1);

      for (var i = lastIncludedIndex + 1; i <= cappedMoveIndex; i++) {
        final chessMove = currentLine[i];
        final parsed = Move.parse(chessMove.uci);
        position = Position.setupPosition(
          Rule.chess,
          Setup.parseFen(chessMove.fen),
        );
        positions.add(position);
        sanMoves.add(chessMove.san);
        moveObjects.add(parsed);
      }

      lastIncludedIndex = cappedMoveIndex;
      pointerIndex++;
      if (pointerIndex >= pointer.length) {
        break;
      }

      final variationIndex = pointer[pointerIndex].toInt();
      pointerIndex++;

      if (lastIncludedIndex < 0 || lastIncludedIndex >= currentLine.length) {
        break;
      }

      final baseMove = currentLine[lastIncludedIndex];
      final variations = baseMove.variations;
      if (variations == null ||
          variationIndex < 0 ||
          variationIndex >= variations.length) {
        break;
      }
      currentLine = variations[variationIndex];
      lastIncludedIndex = -1;
    }

    return _BranchHistory(
      sanMoves: sanMoves,
      moveObjects: moveObjects,
      positions: positions,
    );
  }

  void navigateToPreviewCardIndex(int targetIndex) {
    _navigateToLockedPvIndex(targetIndex);
  }

  /// Apply preview history and insert a new move from a tapped PV card
  /// This commits the preview position to the game history and adds the new move
  void applyPreviewHistoryAndInsertMove(AnalysisLine line) {
    _releaseLog('🎯 APPLY PREVIEW HISTORY AND INSERT MOVE');
    final currentState = state.value;
    if (currentState == null) return;
    if (currentState.lockedPvLine == null ||
        currentState.lockedPvMergedMoves == null) {
      _releaseLog('🎯 APPLY PREVIEW: No locked PV found, aborting');
      return;
    }
    if (_analysisNavigator == null) {
      _releaseLog('🎯 APPLY PREVIEW: No navigator available');
      return;
    }

    final lockedLine = currentState.lockedPvLine!;
    final currentNavIndex = currentState.lockedPvNavigationIndex ?? -1;
    final totalPvMoves = lockedLine.moves.length;

    _releaseLog(
      '🎯 APPLY PREVIEW: currentNavIndex=$currentNavIndex, lockedPvMoves=$totalPvMoves',
    );

    final movesToCommit = math.min(
      totalPvMoves,
      math.max(0, currentNavIndex + 1),
    );
    _releaseLog('🎯 APPLY PREVIEW: Need to commit $movesToCommit PV moves');

    final basePointerSource =
        _pvPreviewSnapshot?.analysisState.movePointer ??
        currentState.analysisState.movePointer;
    final basePointer = List<Number>.of(basePointerSource);

    _ensureNavigatorPointerSynced(basePointer);

    for (int i = 0; i < movesToCommit; i++) {
      final move = lockedLine.moves[i];
      _releaseLog(
        '🎯 APPLY PREVIEW: Committing PV move ${i + 1}/$movesToCommit: ${move.uci}',
      );
      _analysisNavigator!.makeOrGoToMove(move.uci);
    }

    // Clear preview state
    _pvPreviewSnapshot = null;
    state = AsyncValue.data(
      currentState.copyWith(
        isPvPreviewActive: false,
        pvPreviewVariantIndex: null,
        pvPreviewMoveIndex: null,
        lockedPvLine: null,
        lockedPvMergedMoves: null,
        lockedPvMergedMoveObjects: null,
        lockedPvMergedPositions: null,
        lockedPvBaseMoveCount: null,
        lockedPvNavigationIndex: null,
      ),
    );

    _releaseLog(
      '🎯 APPLY PREVIEW: Preview state cleared, now inserting new move',
    );

    // Now insert the first move from the tapped PV card
    if (line.moves.isNotEmpty) {
      final firstMove = line.moves.first;
      _releaseLog('🎯 APPLY PREVIEW: Inserting new move: ${firstMove.uci}');
      _ensureNavigatorPointerSynced();
      _analysisNavigator!.makeOrGoToMove(firstMove.uci);

      final (_, san) = currentState.analysisState.position.makeSan(firstMove);
      _playSoundForSan(san);
    }

    // Trigger fresh evaluation
    _updateEvaluation(force: true);
    _releaseLog('🎯 APPLY PREVIEW: Complete');
  }

  Future<void> promotePreviewToMainVariant() async {
    _releaseLog('🎯 PROMOTE PREVIEW: Replacing main variant with preview line');
    final currentState = state.value;
    if (currentState == null) return;
    if (_analysisNavigator == null) {
      _releaseLog('🎯 PROMOTE PREVIEW: No navigator available');
      return;
    }
    final lockedSans = currentState.lockedPvMergedMoves;
    final lockedMoves = currentState.lockedPvMergedMoveObjects;
    final lockedPositions = currentState.lockedPvMergedPositions;
    if (lockedSans == null ||
        lockedMoves == null ||
        lockedPositions == null ||
        lockedMoves.isEmpty) {
      _releaseLog('🎯 PROMOTE PREVIEW: Missing locked PV data');
      return;
    }

    final startingPosition =
        lockedPositions.isNotEmpty
            ? lockedPositions.first
            : currentState.analysisState.startingPosition ??
                currentState.position;
    if (startingPosition == null) {
      _releaseLog('🎯 PROMOTE PREVIEW: Unable to determine starting position');
      return;
    }

    final newMainline = <ChessMove>[];
    Position cursor = startingPosition;
    for (int i = 0; i < lockedMoves.length; i++) {
      final move = lockedMoves[i];
      final Position resultPosition;
      if (i + 1 < lockedPositions.length) {
        resultPosition = lockedPositions[i + 1];
      } else if (move != null) {
        resultPosition = cursor.play(move);
      } else {
        resultPosition = cursor;
      }

      final san = i < lockedSans.length ? lockedSans[i] : move?.uci ?? '--';
      final chessMove = ChessMove(
        num: resultPosition.fullmoves,
        fen: resultPosition.fen,
        san: san,
        uci: move?.uci ?? '0000',
        turn:
            resultPosition.turn == Side.black
                ? ChessColor.black
                : ChessColor.white,
      );
      newMainline.add(chessMove);
      cursor = resultPosition;
    }

    final existingGame =
        currentState.analysisState.game ?? _analysisNavigator!.state.game;
    final metadata = Map<String, dynamic>.from(existingGame.metadata);
    final newGame = ChessGame(
      gameId: existingGame.gameId,
      startingFen: startingPosition.fen,
      metadata: metadata,
      mainline: newMainline,
    );

    final movePointer =
        newMainline.isEmpty
            ? const <Number>[]
            : <Number>[newMainline.length - 1];

    _analysisNavigator!.replaceState(
      ChessGameNavigatorState(game: newGame, movePointer: movePointer),
    );

    final newPgn = exportGameToPgn(newGame);

    _pvPreviewSnapshot = null;
    state = AsyncValue.data(
      currentState.copyWith(
        isPvPreviewActive: false,
        pvPreviewVariantIndex: null,
        pvPreviewMoveIndex: null,
        lockedPvLine: null,
        lockedPvMergedMoves: null,
        lockedPvMergedMoveObjects: null,
        lockedPvMergedPositions: null,
        lockedPvBaseMoveCount: null,
        lockedPvNavigationIndex: null,
        principalVariations: const [],
        selectedVariantIndex: null,
        variantBaseFen: null,
        variantMovePointer: const [],
        pgnData: newPgn,
      ),
    );

    _syncAnalysisFromNavigator(_analysisNavigator!.state);
    await _persistAnalysisState();
    _updateEvaluation(force: true);
    _releaseLog('🎯 PROMOTE PREVIEW: Promotion complete');
  }

  ChessLine? _extractMainlineFromPointer(
    ChessGame game,
    ChessMovePointer pointer,
  ) {
    if (game.mainline.isEmpty) {
      return const <ChessMove>[];
    }
    ChessLine? currentLine = game.mainline;
    final branch = <ChessMove>[];
    var pointerIndex = 0;
    var lastIncludedIndex = -1;

    while (currentLine != null) {
      if (pointerIndex >= pointer.length) {
        for (var i = lastIncludedIndex + 1; i < currentLine.length; i++) {
          branch.add(_stripVariations(currentLine[i]));
        }
        break;
      }

      final index = pointer[pointerIndex].toInt();
      if (pointerIndex.isEven) {
        if (index >= currentLine.length) {
          return null;
        }
        for (var i = lastIncludedIndex + 1; i <= index; i++) {
          branch.add(_stripVariations(currentLine[i]));
        }
        lastIncludedIndex = index;
        pointerIndex++;
      } else {
        if (lastIncludedIndex < 0 || lastIncludedIndex >= currentLine.length) {
          return null;
        }
        final variations = currentLine[lastIncludedIndex].variations;
        if (variations == null || index >= variations.length) {
          return null;
        }
        currentLine = variations[index];
        lastIncludedIndex = -1;
        pointerIndex++;
      }
    }

    return branch;
  }

  ChessMove _stripVariations(ChessMove move) {
    return move.copyWith(variations: null, overrideVariations: true);
  }

  void navigateLockedPvForward() {
    final currentState = state.value;
    if (currentState == null) {
      return;
    }
    if (!currentState.isPvPreviewActive) {
      return;
    }
    final pvLine = currentState.lockedPvLine;
    if (pvLine == null) {
      return;
    }

    final currentIndex = currentState.lockedPvNavigationIndex ?? -1;
    final maxIndex = pvLine.moves.length - 1;
    if (maxIndex < 0 || currentIndex >= maxIndex) {
      return;
    }

    final newIndex = currentIndex < 0 ? 0 : currentIndex + 1;
    _navigateToLockedPvIndex(newIndex);
  }

  void navigateLockedPvBackward() {
    final currentState = state.value;
    if (currentState == null) {
      return;
    }
    if (!currentState.isPvPreviewActive) {
      return;
    }
    final pvLine = currentState.lockedPvLine;
    if (pvLine == null) {
      return;
    }

    final currentIndex = currentState.lockedPvNavigationIndex ?? -1;

    if (currentIndex <= 0) {
      _navigateToLockedPvIndex(0);
      return;
    }

    final newIndex = currentIndex - 1;
    _navigateToLockedPvIndex(newIndex);
  }

  void _navigateToLockedPvIndex(int targetIndex, {bool force = false}) {
    final currentState = state.value;
    if (currentState == null) return;
    final mergedMoves = currentState.lockedPvMergedMoves;
    final moveObjects = currentState.lockedPvMergedMoveObjects;
    final positions = currentState.lockedPvMergedPositions;
    final baseCount = currentState.lockedPvBaseMoveCount ?? 0;
    final pvMoveCount = currentState.lockedPvLine?.moves.length ?? 0;
    if (mergedMoves == null ||
        moveObjects == null ||
        positions == null ||
        pvMoveCount == 0) {
      return;
    }
    if (moveObjects.isEmpty || positions.length != moveObjects.length + 1) {
      return;
    }

    final maxPvIndex = pvMoveCount - 1;
    final clampedPvIndex = targetIndex.clamp(0, maxPvIndex);
    if (!force &&
        clampedPvIndex == (currentState.lockedPvNavigationIndex ?? -1)) {
      return;
    }

    final absoluteIndex = baseCount + clampedPvIndex;
    if (absoluteIndex < 0 || absoluteIndex >= moveObjects.length) {
      return;
    }
    if (absoluteIndex + 1 >= positions.length) {
      return;
    }

    final position = positions[absoluteIndex + 1];
    final lastMove = moveObjects[absoluteIndex];

    final updatedAnalysis = currentState.analysisState.copyWith(
      position: position,
      lastMove: lastMove,
      validMoves: makeLegalMoves(position),
    );

    state = AsyncValue.data(
      currentState.copyWith(
        analysisState: updatedAnalysis,
        lockedPvNavigationIndex: clampedPvIndex,
        pvPreviewMoveIndex: clampedPvIndex,
        isEvaluating: true,
      ),
    );

    // Keep eval bar alive during preview navigation; PV arrows/cards stay suppressed elsewhere
    _updateEvaluation(
      force: true,
      preserveCurrentPvs: true,
      preserveDepthProgress: true,
    );
  }

  /// Select a variant (engine suggestion) for navigation
  void selectVariant(
    int variantIndex, {
    bool forceReset = false,
    bool preservePreview = false,
  }) {
    _releaseLog(
      '🎯 SELECT VARIANT: index=$variantIndex, preservePreview=$preservePreview',
    );
    if (!preservePreview) {
      _exitPvPreviewIfActive();
    }
    final currentState = state.value;
    if (currentState == null) {
      _releaseLog('🎯 SELECT VARIANT: FAILED - state null');
      return;
    }
    if (variantIndex < 0 ||
        variantIndex >= currentState.principalVariations.length) {
      _releaseLog(
        '🎯 SELECT VARIANT: FAILED - invalid index (pvs=${currentState.principalVariations.length})',
      );
      return;
    }

    // CRITICAL: If same variant already selected, don't reset - just return
    if (!forceReset && currentState.selectedVariantIndex == variantIndex) {
      _releaseLog('🎯 SELECT VARIANT: Already selected, skipping re-selection');
      return;
    }

    // CRITICAL: Lock the EXACT current position as the base for this variant exploration
    final baseFen = currentState.analysisState.position.fen;
    final basePointer = currentState.analysisState.movePointer;

    _releaseLog(
      '🎯 SELECT VARIANT: Locking base state (fen=$baseFen, pointer=$basePointer)',
    );

    // Show all variants as arrows (unless preview is active)
    final arrowShapes = _maybeSuppressShapes(
      currentState,
      _getAllVariantArrowShapes(
        currentState.principalVariations,
        variantIndex,
        isThreatsMode: currentState.isThreatsMode,
      ),
    );

    // When preserving preview mode, explicitly maintain all preview-related state
    final updatedState =
        preservePreview
            ? currentState.copyWith(
              selectedVariantIndex: variantIndex,
              variantMovePointer: const [],
              variantBaseFen: baseFen,
              variantBaseMovePointer: basePointer,
              variantBaseLastMove: currentState.analysisState.lastMove,
              variantBaseMoveIndex: currentState.analysisState.currentMoveIndex,
              shapes: arrowShapes,
              // Explicitly preserve preview state to prevent accidental exit
              isPvPreviewActive: currentState.isPvPreviewActive,
              pvPreviewVariantIndex: currentState.pvPreviewVariantIndex,
              pvPreviewMoveIndex: currentState.pvPreviewMoveIndex,
              lockedPvLine: currentState.lockedPvLine,
              lockedPvMergedMoves: currentState.lockedPvMergedMoves,
              lockedPvMergedMoveObjects: currentState.lockedPvMergedMoveObjects,
              lockedPvMergedPositions: currentState.lockedPvMergedPositions,
              lockedPvBaseMoveCount: currentState.lockedPvBaseMoveCount,
              lockedPvNavigationIndex: currentState.lockedPvNavigationIndex,
            )
            : currentState.copyWith(
              selectedVariantIndex: variantIndex,
              variantMovePointer: const [],
              variantBaseFen: baseFen,
              variantBaseMovePointer: basePointer,
              variantBaseLastMove: currentState.analysisState.lastMove,
              variantBaseMoveIndex: currentState.analysisState.currentMoveIndex,
              shapes: arrowShapes,
            );

    _resumeVariantAutoPlay = false;
    _isPlayingVariant = false;
    state = AsyncValue.data(updatedState);

    _releaseLog('🎯 SELECT VARIANT: Variant selected, base locked');
  }

  /// Play next move of the selected variant forward
  void playVariantMoveForward() {
    _releaseLog('🎯 PLAY VARIANT FORWARD called');
    if (_isEditingBlockedByPreview(reason: 'variant forward')) {
      return;
    }
    _exitPvPreviewIfActive();

    // CRITICAL: Prevent concurrent execution
    if (_isPlayingVariant) {
      _releaseLog('🎯 PLAY VARIANT FORWARD: Already playing, skipping');
      return;
    }
    _isPlayingVariant = true;

    try {
      var currentState = state.value;
      if (currentState == null) {
        _releaseLog('🎯 PLAY VARIANT FORWARD: State is null');
        return;
      }
      if (!_ensureVariantSelection()) {
        _releaseLog('🎯 PLAY VARIANT FORWARD: No variants available');
        return;
      }
      currentState = state.value;
      if (currentState == null || currentState.selectedVariantIndex == null) {
        _releaseLog('🎯 PLAY VARIANT FORWARD: Variant selection failed');
        return;
      }

      // CRITICAL: Validate variant navigation is safe
      if (!_isVariantNavigationValid(currentState)) {
        _releaseLog(
          '🎯 PLAY VARIANT FORWARD: Variant navigation invalid, clearing stale PVs',
        );
        _releaseLog(
          '🎯 PLAY VARIANT FORWARD: New PVs will be calculated for current position',
        );
        // Clear variant selection AND old PVs, then trigger fresh evaluation
        final clearedState = _clearVariantSelection(currentState).copyWith(
          principalVariations: const [],
          principalVariationsBaseFen: null,
          isEvaluating: true,
        );
        state = AsyncValue.data(clearedState);
        _updateEvaluation(
          force: true,
        ); // Force fresh evaluation for current position
        return;
      }

      if (currentState.variantBaseFen == null) {
        _releaseLog('🎯 PLAY VARIANT FORWARD: Missing base FEN, aborting');
        return;
      }

      final selectedVariant =
          currentState.principalVariations[currentState.selectedVariantIndex!];
      final nextMoveIndex = currentState.variantMovePointer.length;

      _releaseLog(
        '🎯 PLAY VARIANT FORWARD: nextMoveIndex=$nextMoveIndex, variantLength=${selectedVariant.moves.length}',
      );

      if (nextMoveIndex >= selectedVariant.moves.length) {
        if (!_resumeVariantAutoPlay) {
          _releaseLog(
            '🎯 PLAY VARIANT FORWARD: Reached end of variant, requesting extension',
          );
          _resumeVariantAutoPlay = true;
          final currentFen = currentState.analysisState.position.fen;
          // CRITICAL: Update variant base to CURRENT position for extension
          // The new PVs will start from here, and variantMovePointer resets to []
          final updatedForExtension = currentState.copyWith(
            isEvaluating: true,
            variantBaseFen: currentFen,
            variantBaseMovePointer: currentState.analysisState.movePointer,
            variantMovePointer: const [], // Reset pointer for new base
          );
          state = AsyncValue.data(updatedForExtension);

          _releaseLog(
            '🎯 PLAY VARIANT FORWARD: Extension base set to $currentFen, resetting pointer',
          );
          _updateEvaluation(force: true);
        } else {
          _releaseLog(
            '🎯 PLAY VARIANT FORWARD: Extension already in progress, waiting',
          );
        }
        return;
      }

      _resumeVariantAutoPlay = false;

      final nextMove = selectedVariant.moves[nextMoveIndex];
      _releaseLog('🎯 PLAY VARIANT FORWARD: Next move UCI=${nextMove.uci}');

      if (nextMove is NormalMove && isPromotionPawnMove(nextMove)) {
        state = AsyncValue.data(
          currentState.copyWith(
            analysisState: currentState.analysisState.copyWith(
              promotionMove: nextMove,
            ),
          ),
        );
        return;
      }

      // NEW APPROACH: Commit the move to the navigator instead of just exploring
      // This makes PV moves part of the permanent analysis history
      if (_analysisNavigator != null) {
        _releaseLog('🎯 PLAY VARIANT FORWARD: Committing move to navigator');
        final (positionAfterMove, san) = currentState.analysisState.position
            .makeSan(nextMove);

        final rebasedState = _rebaseVariantAfterCommittedMove(
          currentState: currentState,
          committedMoveIndex: nextMoveIndex,
          positionAfterMove: positionAfterMove,
          committedMove: nextMove,
        );
        state = AsyncValue.data(rebasedState);

        // Make move through navigator - this is now the single source of truth
        _ensureNavigatorPointerSynced();
        _analysisNavigator!.makeOrGoToMove(nextMove.uci);
        _playSoundForSan(san);

        final navigatorSnapshot =
            _analysisGame == null
                ? null
                : ref.read(chessGameNavigatorProvider(_analysisGame!));
        if (navigatorSnapshot != null) {
          final latestState = state.value;
          if (latestState != null && latestState.selectedVariantIndex != null) {
            state = AsyncValue.data(
              latestState.copyWith(
                variantBaseMovePointer: navigatorSnapshot.movePointer,
                variantBaseMoveIndex:
                    navigatorSnapshot.movePointer.isEmpty
                        ? null
                        : navigatorSnapshot.movePointer.last.toInt(),
              ),
            );
          }
        }

        // Trigger new evaluation for the new position
        // Cache will be checked first, fresh eval if needed
        _updateEvaluation(
          force: true,
          preserveCurrentPvs: true,
          preserveDepthProgress: true,
        );
        return;
      }

      // FALLBACK: Old pointer-based navigation if navigator unavailable
      _releaseLog(
        '🎯 PLAY VARIANT FORWARD: FALLBACK - Navigator unavailable, using pointer',
      );
      final newPointer = List<int>.from(currentState.variantMovePointer)
        ..add(nextMoveIndex);

      Position positionAfter;
      try {
        positionAfter = _variantPositionFromBase(
          currentState,
          selectedVariant,
          newPointer.length,
        );
      } catch (e) {
        _releaseLog(
          '🎯 PLAY VARIANT FORWARD: ERROR - Variant moves don\'t match base position',
        );
        _releaseLog('   Error: $e');
        _releaseLog('   Base FEN: ${currentState.variantBaseFen}');
        _releaseLog(
          '   Current FEN: ${currentState.analysisState.position.fen}',
        );
        _releaseLog('   Moves to apply: ${newPointer.length}');
        _releaseLog(
          '   Variant moves: ${selectedVariant.moves.map((m) => m.uci).join(" ")}',
        );
        _releaseLog(
          '🎯 PLAY VARIANT FORWARD: Clearing stale variant and triggering fresh evaluation',
        );
        // Clear stale variant and PVs, trigger fresh evaluation
        final clearedState = _clearVariantSelection(currentState).copyWith(
          principalVariations: const [],
          principalVariationsBaseFen: null,
          isEvaluating: true,
        );
        state = AsyncValue.data(clearedState);
        _updateEvaluation();
        return;
      }

      final updatedState = currentState.copyWith(
        variantMovePointer: newPointer,
        analysisState: currentState.analysisState.copyWith(
          position: positionAfter,
          lastMove: nextMove,
          currentMoveIndex:
              currentState.variantBaseMoveIndex ??
              currentState.analysisState.currentMoveIndex,
          validMoves: makeLegalMoves(positionAfter),
          promotionMove: null,
        ),
      );

      // Show all variants as arrows (unless suppressed)
      final arrowShapes = _maybeSuppressShapes(
        updatedState,
        _getAllVariantArrowShapes(
          currentState.principalVariations,
          currentState.selectedVariantIndex!,
          isThreatsMode: currentState.isThreatsMode,
        ),
      );

      state = AsyncValue.data(updatedState.copyWith(shapes: arrowShapes));
      final sanMoves = selectedVariant.sanMoves;
      if (nextMoveIndex < sanMoves.length) {
        _playSoundForSan(sanMoves[nextMoveIndex]);
      }
      _updateEvaluation();
    } finally {
      _isPlayingVariant = false;
    }
  }

  /// Undo last move of the selected variant OR navigator move
  void playVariantMoveBackward() {
    _releaseLog('🎯 PLAY VARIANT BACKWARD called');
    if (_isEditingBlockedByPreview(reason: 'variant backward')) {
      return;
    }
    _exitPvPreviewIfActive();
    _resumeVariantAutoPlay = false;
    var currentState = state.value;
    if (currentState == null) {
      _releaseLog('🎯 PLAY VARIANT BACKWARD: State is null');
      return;
    }

    // NEW APPROACH: If no active variant pointer, use navigator undo
    // This handles moves that were committed (via forward PV or manual board moves)
    if (currentState.variantMovePointer.isEmpty ||
        currentState.selectedVariantIndex == null) {
      _releaseLog(
        '🎯 PLAY VARIANT BACKWARD: No active variant exploration, using navigator undo',
      );
      if (_analysisNavigator != null) {
        final navigatorState = ref.read(
          chessGameNavigatorProvider(_analysisGame!),
        );
        if (navigatorState.movePointer.isNotEmpty) {
          _releaseLog('🎯 PLAY VARIANT BACKWARD: Navigator undo available');
          analysisStepBackward();
        } else {
          _releaseLog('🎯 PLAY VARIANT BACKWARD: At start of game');
        }
      } else {
        _releaseLog('🎯 PLAY VARIANT BACKWARD: Navigator unavailable');
        analysisStepBackward();
      }
      return;
    }

    // OLD APPROACH: Handle pointer-based variant exploration (fallback)
    if (!_ensureVariantSelection()) {
      _releaseLog('🎯 PLAY VARIANT BACKWARD: No variants available');
      return;
    }
    currentState = state.value;
    if (currentState == null || currentState.selectedVariantIndex == null) {
      _releaseLog('🎯 PLAY VARIANT BACKWARD: Variant selection failed');
      return;
    }

    // CRITICAL: Validate variant navigation is safe
    if (!_isVariantNavigationValid(currentState)) {
      _releaseLog(
        '🎯 PLAY VARIANT BACKWARD: Variant navigation invalid, clearing stale PVs',
      );
      _releaseLog(
        '🎯 PLAY VARIANT BACKWARD: New PVs will be calculated for current position',
      );
      // Clear variant selection AND old PVs, then trigger fresh evaluation
      final clearedState = _clearVariantSelection(currentState).copyWith(
        principalVariations: const [],
        principalVariationsBaseFen: null,
        isEvaluating: true,
      );
      state = AsyncValue.data(clearedState);
      _updateEvaluation(
        force: true,
      ); // Force fresh evaluation for current position
      return;
    }

    if (currentState.variantMovePointer.isEmpty) {
      _releaseLog(
        '🎯 PLAY VARIANT BACKWARD: Already at variant start, reverting to main line',
      );
      analysisStepBackward();
      return;
    }

    final newPointer = List<int>.from(currentState.variantMovePointer)
      ..removeLast();
    final appliedCount = newPointer.length;
    final selectedVariant =
        currentState.principalVariations[currentState.selectedVariantIndex!];
    final positionAfter = _variantPositionFromBase(
      currentState,
      selectedVariant,
      appliedCount,
    );

    final lastMove =
        appliedCount > 0
            ? selectedVariant.moves[appliedCount - 1]
            : currentState.variantBaseLastMove;

    final updatedState = currentState.copyWith(
      variantMovePointer: newPointer,
      analysisState: currentState.analysisState.copyWith(
        position: positionAfter,
        lastMove: lastMove,
        currentMoveIndex:
            currentState.variantBaseMoveIndex ??
            currentState.analysisState.currentMoveIndex,
        validMoves: makeLegalMoves(positionAfter),
        promotionMove: null,
      ),
    );

    final arrowShapes = _maybeSuppressShapes(
      updatedState,
      _variantArrowShapes(
        selectedVariant,
        newPointer.length,
        isThreatsMode: currentState.isThreatsMode,
      ),
    );

    state = AsyncValue.data(updatedState.copyWith(shapes: arrowShapes));
    final sanMoves = selectedVariant.sanMoves;
    if (appliedCount < sanMoves.length) {
      final sanForUndo = sanMoves[appliedCount];
      _playSoundForSan(sanForUndo);
    } else {
      _playSoundForSan('');
    }
    _updateEvaluation();
  }

  void cycleVariant(int delta) {
    final currentState = state.value;
    if (currentState == null ||
        !currentState.isAnalysisMode ||
        currentState.principalVariations.isEmpty) {
      return;
    }

    final count = currentState.principalVariations.length;
    int targetIndex;
    final currentIndex = currentState.selectedVariantIndex;
    if (currentIndex == null) {
      targetIndex = delta > 0 ? 0 : count - 1;
    } else {
      targetIndex = (currentIndex + delta) % count;
      if (targetIndex < 0) {
        targetIndex += count;
      }
      if (targetIndex == currentIndex) {
        return;
      }
    }
    selectVariant(targetIndex);
  }

  Future<void> moveForward() async {
    await _queueNavigation(1);
  }

  Future<void> moveBackward() async {
    await _queueNavigation(-1);
  }

  Future<void> _queueNavigation(int delta) {
    if (delta == 0 || !mounted) return Future.value();
    final request = _NavigationRequest(delta);
    _navigationQueue.add(request);
    if (!_isNavigationProcessing) {
      unawaited(_processQueuedNavigation());
    }
    return request.completer.future;
  }

  Future<void> _processQueuedNavigation() async {
    if (_isNavigationProcessing || !mounted) return;
    _isNavigationProcessing = true;
    try {
      while (mounted && _navigationQueue.isNotEmpty) {
        final request = _navigationQueue.removeAt(0);
        final step = request.delta >= 0 ? 1 : -1;
        final didMove =
            step > 0
                ? await _moveForwardInternal()
                : await _moveBackwardInternal();
        if (!request.completer.isCompleted) {
          request.completer.complete();
        }
        if (!didMove) {
          // Drop any remaining queued steps in the same direction.
          _navigationQueue.removeWhere(
            (pending) => (pending.delta >= 0) == (step > 0),
          );
          break;
        }
        // Yield to allow navigator/listeners to settle between rapid steps.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _isNavigationProcessing = false;
    }
  }

  Future<bool> _moveForwardInternal() async {
    final currentState = state.value;

    // If in preview mode with locked PV, navigate within locked PV
    if (currentState?.isPvPreviewActive == true &&
        currentState?.lockedPvLine != null) {
      final pvLine = currentState!.lockedPvLine!;
      final currentIndex = currentState.lockedPvNavigationIndex ?? -1;
      final maxIndex = pvLine.moves.length - 1;
      final canAdvance = maxIndex >= 0 && currentIndex < maxIndex;
      if (!canAdvance) return false;
      navigateLockedPvForward();
      return true;
    }

    _exitPvPreviewIfActive();
    // Bottom nav arrows should navigate within the active context
    // (analysis variation or main game) without forcing a mode change
    if (currentState == null || _isProcessingMove) {
      return false;
    }

    final canAdvance =
        currentState.isAnalysisMode
            ? _canAnalysisNavigatorMoveForward()
            : currentState.canMoveForward;

    if (!canAdvance) {
      return false;
    }

    if (currentState.isAnalysisMode) {
      analysisStepForward();
      return true;
    }

    await goToMove(currentState.currentMoveIndex + 1);
    return true;
  }

  Future<bool> _moveBackwardInternal() async {
    final currentState = state.value;

    // If in preview mode with locked PV, navigate within locked PV
    if (currentState?.isPvPreviewActive == true &&
        currentState?.lockedPvLine != null) {
      final pvLine = currentState!.lockedPvLine!;
      final currentIndex = currentState.lockedPvNavigationIndex ?? -1;
      final maxIndex = pvLine.moves.length - 1;
      final canRetreat =
          maxIndex >= 0 && (currentIndex > 0 || currentIndex == -1);
      if (!canRetreat) return false;
      navigateLockedPvBackward();
      return true;
    }

    _exitPvPreviewIfActive();
    if (currentState == null || _isProcessingMove) {
      return false;
    }

    final canRetreat =
        currentState.isAnalysisMode
            ? _canAnalysisNavigatorMoveBackward()
            : currentState.canMoveBackward;

    if (!canRetreat) {
      return false;
    }

    if (currentState.isAnalysisMode) {
      analysisStepBackward();
      return true;
    }

    await goToMove(currentState.currentMoveIndex - 1);
    return true;
  }

  // REMOVED: toggleAnalysisMode - analysis mode is always active and cannot be toggled

  Future<void> _initializeAnalysisBoard() async {
    if (_analysisGame != null) {
      return;
    }

    final currentState = state.value;
    if (currentState == null) return;

    // Check if we're restoring from saved analysis
    if (savedAnalysisData != null) {
      // Use the pre-built ChessGame with all variations directly
      _analysisGame = savedAnalysisData!.chessGame;
      debugPrint(
        '🎯 ChessBoard[$index]: Using saved ChessGame with ${_analysisGame!.mainline.length} moves',
      );
    } else {
      // Ensure PGN is available
      if (currentState.pgnData == null) {
        await parseMoves();
      }

      final updatedState = state.value;
      if (updatedState == null || updatedState.pgnData == null) {
        return;
      }

      final pgn = updatedState.pgnData!;
      _analysisGame = _createChessGameFromPgn(pgn);
    }

    _analysisStateManager = ChessGameNavigatorStateManager();

    final navigator = ref.read(
      chessGameNavigatorProvider(_analysisGame!).notifier,
    );

    // Determine the initial move position
    // Priority: savedAnalysisData.movePointer > savedAnalysisData.lastViewedPosition > currentState.currentMoveIndex
    List<int> movePointer;
    if (savedAnalysisData != null &&
        savedAnalysisData!.movePointer != null &&
        savedAnalysisData!.movePointer!.isNotEmpty) {
      // Use saved move pointer to restore exact position in variation tree
      movePointer = savedAnalysisData!.movePointer!;
      debugPrint(
        '🎯 ChessBoard[$index]: Restoring saved movePointer: $movePointer',
      );
    } else if (savedAnalysisData != null &&
        savedAnalysisData!.lastViewedPosition >= 0) {
      // Use saved last viewed position
      movePointer = [savedAnalysisData!.lastViewedPosition];
      debugPrint(
        '🎯 ChessBoard[$index]: Restoring lastViewedPosition: ${savedAnalysisData!.lastViewedPosition}',
      );
    } else {
      // Use current state's move index
      final currentMoveIndex = currentState.currentMoveIndex;
      movePointer = currentMoveIndex < 0 ? const <int>[] : [currentMoveIndex];
    }

    _releaseLog(
      '===== ANALYSIS MODE: Initializing with movePointer: $movePointer =====',
    );

    // Set up listener BEFORE replaceState to capture the state change
    _navigatorSubscription?.close();
    _navigatorSubscription = ref.listen<ChessGameNavigatorState>(
      chessGameNavigatorProvider(_analysisGame!),
      (previous, next) {
        _releaseLog(
          '===== ANALYSIS MODE: Navigator state changed, movePointer: ${next.movePointer} =====',
        );
        _syncAnalysisFromNavigator(next);
      },
      fireImmediately:
          false, // Don't fire immediately - we'll sync manually after replaceState
    );

    // Initialize navigator with determined move pointer.
    // Defer to microtask to avoid mutating another provider during build.
    Future.microtask(() {
      if (!mounted) return;
      navigator.replaceState(
        ChessGameNavigatorState(game: _analysisGame!, movePointer: movePointer),
      );

      // Manually sync the initial state after replaceState
      final initialState = ref.read(chessGameNavigatorProvider(_analysisGame!));
      _syncAnalysisFromNavigator(initialState);
    });
  }

  Future<void> _persistAnalysisState() async {
    if (_analysisGame == null || _analysisStateManager == null) return;

    final navigatorState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    await _analysisStateManager!.saveState(navigatorState);
  }

  /// Called after the save-analysis sheet creates a new row in Supabase.
  /// Sets the analysis ID so that auto-save and manual update start working.
  void attachSavedAnalysisId({
    required String analysisId,
    required String title,
    String? folderId,
  }) {
    final currentState = state.valueOrNull;
    savedAnalysisData = SavedAnalysisData(
      analysisId: analysisId,
      chessGame: currentState?.analysisState.game ?? savedAnalysisData!.chessGame,
      variationComments: currentState?.variationComments ?? const {},
      isBoardFlipped: currentState?.isBoardFlipped ?? false,
      lastViewedPosition: currentState?.analysisState.currentMoveIndex ?? 0,
      title: title,
      folderId: folderId,
    );
    // Snapshot current game tree so auto-save doesn't immediately re-save
    final analysisGame = currentState?.analysisState.game;
    if (analysisGame != null) {
      _lastAutoSavedGameJson = analysisGame.toJson().toString();
    }
    // Emit a state change so the save button rebuilds to show auto-save icon
    if (currentState != null) {
      state = AsyncValue.data(
        currentState.copyWith(autoSaveStatus: AutoSaveStatus.saved),
      );
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final s = state.valueOrNull;
        if (s != null && s.autoSaveStatus == AutoSaveStatus.saved) {
          state = AsyncValue.data(
            s.copyWith(autoSaveStatus: AutoSaveStatus.idle),
          );
        }
      });
    }
    debugPrint('🎯 ChessBoard[$index]: Attached saved analysis ID=$analysisId');
  }

  /// Performs an immediate save update to the existing library analysis.
  /// Returns true on success, false on failure.
  Future<bool> performManualUpdate() async {
    _autoSaveTimer?.cancel();
    final analysisId = savedAnalysisData?.analysisId;
    if (analysisId == null) return false;

    final currentState = state.valueOrNull;
    if (currentState == null) return false;

    final analysisGame = currentState.analysisState.game;
    if (analysisGame == null) return false;

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final userId = repository.supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final analysisStateJson = <String, dynamic>{
        'move_pointer': currentState.analysisState.movePointer,
        'is_board_flipped': currentState.isBoardFlipped,
      };

      final savedAnalysis = SavedAnalysis(
        id: analysisId,
        userId: userId,
        folderId: savedAnalysisData?.folderId,
        title: savedAnalysisData?.title ?? currentState.game.whitePlayer.name +
            ' vs ' + currentState.game.blackPlayer.name,
        chessGame: analysisGame,
        analysisState: analysisStateJson,
        variationComments: currentState.variationComments,
        lastViewedPosition: currentState.analysisState.currentMoveIndex,
        tags: const [],
        isFavorite: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.updateSavedAnalysis(savedAnalysis);
      _lastAutoSavedGameJson = analysisGame.toJson().toString();

      if (!mounted) return true;
      final s = state.valueOrNull;
      if (s != null) {
        state = AsyncValue.data(
          s.copyWith(autoSaveStatus: AutoSaveStatus.saved),
        );
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          final s2 = state.valueOrNull;
          if (s2 != null && s2.autoSaveStatus == AutoSaveStatus.saved) {
            state = AsyncValue.data(
              s2.copyWith(autoSaveStatus: AutoSaveStatus.idle),
            );
          }
        });
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ Manual update failed: $e');
      return false;
    }
  }

  /// Schedule a debounced auto-save to Supabase for library games.
  /// Only activates when we have a saved analysis ID to update.
  void _scheduleAutoSave() {
    final analysisId = savedAnalysisData?.analysisId;
    if (analysisId == null) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), _performAutoSave);
  }

  /// Perform the actual auto-save by updating the existing row in Supabase.
  Future<void> _performAutoSave() async {
    final analysisId = savedAnalysisData?.analysisId;
    if (analysisId == null || !mounted) return;

    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final analysisGame = currentState.analysisState.game;
    if (analysisGame == null) return;

    // Check if anything actually changed since last auto-save
    final currentJson = analysisGame.toJson().toString();
    final commentsChanged =
        currentState.variationComments != savedAnalysisData?.variationComments;
    if (currentJson == _lastAutoSavedGameJson && !commentsChanged) return;

    // Set saving status
    state = AsyncValue.data(
      currentState.copyWith(autoSaveStatus: AutoSaveStatus.saving),
    );

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final userId = repository.supabase.auth.currentUser?.id;
      if (userId == null) return;

      final analysisStateJson = <String, dynamic>{
        'move_pointer': currentState.analysisState.movePointer,
        'is_board_flipped': currentState.isBoardFlipped,
      };

      final savedAnalysis = SavedAnalysis(
        id: analysisId,
        userId: userId,
        folderId: savedAnalysisData?.folderId,
        title: savedAnalysisData?.title ?? currentState.game.whitePlayer.name +
            ' vs ' + currentState.game.blackPlayer.name,
        chessGame: analysisGame,
        analysisState: analysisStateJson,
        variationComments: currentState.variationComments,
        lastViewedPosition: currentState.analysisState.currentMoveIndex,
        tags: const [],
        isFavorite: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.updateSavedAnalysis(savedAnalysis);
      _lastAutoSavedGameJson = currentJson;

      if (!mounted) return;
      final afterState = state.valueOrNull;
      if (afterState == null) return;

      state = AsyncValue.data(
        afterState.copyWith(autoSaveStatus: AutoSaveStatus.saved),
      );

      // Reset status back to idle after 1.5s
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final s = state.valueOrNull;
        if (s != null && s.autoSaveStatus == AutoSaveStatus.saved) {
          state = AsyncValue.data(
            s.copyWith(autoSaveStatus: AutoSaveStatus.idle),
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Auto-save failed: $e');
      if (!mounted) return;
      final s = state.valueOrNull;
      if (s != null) {
        state = AsyncValue.data(
          s.copyWith(autoSaveStatus: AutoSaveStatus.idle),
        );
      }
    }
  }

  ChessGame _createChessGameFromPgn(String pgn) {
    final parsed = ChessGame.fromPgn(game.gameId, pgn);
    final needsLiveFlag = game.gameStatus.isOngoing;
    final needsMainlineExtension = game.roundId == 'board_editor';

    if (!needsLiveFlag && !needsMainlineExtension) {
      return parsed;
    }

    final metadata = Map<String, dynamic>.from(parsed.metadata);
    if (needsLiveFlag) {
      metadata[ChessGame.metadataIsLiveKey] = true;
    }
    if (needsMainlineExtension) {
      metadata[ChessGame.metadataAllowMainlineExtensionKey] = true;
    }
    return parsed.copyWith(metadata: metadata);
  }

  bool isPromotionPawnMove(NormalMove move) {
    var currentState = state.value;
    if (currentState == null) return false;
    Position pos =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position!;
    return move.promotion == null &&
        pos.board.roleAt(move.from) == Role.pawn &&
        ((move.to.rank == Rank.first && pos.turn == Side.black) ||
            (move.to.rank == Rank.eighth && pos.turn == Side.white));
  }

  void onAnalysisMove(NormalMove move, {bool? isDrop, bool? isPremove}) {
    _releaseLog(
      '🎯 ANALYSIS MOVE: Received move ${move.uci}, isDrop=$isDrop, isPremove=$isPremove',
    );
    if (_isEditingBlockedByPreview(reason: 'board move')) {
      return;
    }
    _exitPvPreviewIfActive();
    _releaseLog(
      '🎯 ANALYSIS MOVE: _analysisGame is ${_analysisGame == null ? "null" : "not null"}',
    );
    var currentState = state.value;
    if (currentState == null) {
      _releaseLog('🎯 ANALYSIS MOVE: state is null, aborting');
      return;
    }

    final clearedState = _clearVariantSelection(currentState);
    if (!identical(clearedState, currentState)) {
      state = AsyncValue.data(clearedState);
      currentState = clearedState;
    }

    currentState = state.value;
    if (currentState == null) {
      _releaseLog('🎯 ANALYSIS MOVE: state missing after clear, aborting');
      return;
    }

    final boardPosition =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position!;

    try {
      if (!boardPosition.isLegal(move)) {
        _releaseLog(
          '🎯 ANALYSIS MOVE: ERROR - Move ${move.uci} is ILLEGAL in current board position ${boardPosition.fen}',
        );
        _releaseLog('🎯 ANALYSIS MOVE: Turn to move: ${boardPosition.turn}');
        HapticFeedback.heavyImpact();
        return;
      }
    } catch (e) {
      _releaseLog('🎯 ANALYSIS MOVE: ERROR - Failed legality check: $e');
      return;
    }

    if (isPromotionPawnMove(move)) {
      _releaseLog('🎯 ANALYSIS MOVE: Promotion detected, storing move');
      _releaseLog('🎯 ANALYSIS MOVE: Promotion move UCI: ${move.uci}');
      _releaseLog(
        '🎯 ANALYSIS MOVE: Promotion move from: ${move.from}, to: ${move.to}',
      );
      _releaseLog(
        '🎯 ANALYSIS MOVE: Current position FEN: ${boardPosition.fen}',
      );
      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            promotionMove: move,
          ),
        ),
      );
      return;
    }

    if (_analysisGame != null) {
      final navigatorState = ref.read(
        chessGameNavigatorProvider(_analysisGame!),
      );
      final currentFen = navigatorState.currentFen;
      _releaseLog('🎯 ANALYSIS MOVE: Current FEN from navigator: $currentFen');

      if (_normalizeFen(currentFen) == _normalizeFen(boardPosition.fen)) {
        _releaseLog(
          '🎯 ANALYSIS MOVE: Navigator aligned, applying move via navigator',
        );
        const pointerEquality = ListEquality<int>();
        final boardPointer = currentState.analysisState.movePointer;
        if (!pointerEquality.equals(navigatorState.movePointer, boardPointer)) {
          _releaseLog(
            '🎯 ANALYSIS MOVE: Syncing navigator pointer to $boardPointer before move',
          );
          _analysisNavigator?.goToMovePointerUnchecked(boardPointer);
        }
        final (_, san) = boardPosition.makeSan(move);

        _analysisNavigator?.makeOrGoToMove(move.uci);

        // Sync state after navigation
        final updatedState = ref.read(
          chessGameNavigatorProvider(_analysisGame!),
        );
        _syncAnalysisFromNavigator(updatedState);

        HapticFeedback.lightImpact();
        _playSoundForSan(san);
        return;
      } else {
        _releaseLog(
          '🎯 ANALYSIS MOVE: Navigator FEN differs from board, applying manual fallback',
        );
      }
    } else {
      _releaseLog('🎯 ANALYSIS MOVE: _analysisGame is null, using fallback');
    }

    _applyManualAnalysisMove(currentState, boardPosition, move);
  }

  void _applyManualAnalysisMove(
    ChessBoardStateNew currentState,
    Position currentPosition,
    NormalMove move,
  ) {
    try {
      _releaseLog('🎯 MANUAL MOVE FALLBACK: Applying move ${move.uci}');

      // CRITICAL: Navigator must be the single source of truth for analysis moves
      // If navigator is out of sync, this is a bug that should not happen
      if (_analysisNavigator == null) {
        _releaseLog(
          '🎯 MANUAL MOVE FALLBACK: ERROR - Navigator is null, cannot apply move',
        );
        return;
      }

      final navigatorState = ref.read(
        chessGameNavigatorProvider(_analysisGame!),
      );

      if (_normalizeFen(navigatorState.currentFen) !=
          _normalizeFen(currentPosition.fen)) {
        _releaseLog(
          '🎯 MANUAL MOVE FALLBACK: CRITICAL - Navigator out of sync!',
        );
        _releaseLog('   Navigator FEN: ${navigatorState.currentFen}');
        _releaseLog('   Board FEN: ${currentPosition.fen}');
        _releaseLog(
          '   This should not happen - navigator should always match board',
        );
        return;
      }

      // Navigator is in sync, apply move through it
      _releaseLog('🎯 MANUAL MOVE FALLBACK: Navigator in sync, applying move');
      const pointerEquality = ListEquality<int>();
      final boardPointer = currentState.analysisState.movePointer;
      if (!pointerEquality.equals(navigatorState.movePointer, boardPointer)) {
        _analysisNavigator?.goToMovePointerUnchecked(boardPointer);
      }
      _analysisNavigator?.makeOrGoToMove(move.uci);

      // Sync state after navigation
      final updatedState = ref.read(chessGameNavigatorProvider(_analysisGame!));
      _syncAnalysisFromNavigator(updatedState);

      HapticFeedback.lightImpact();
      return;
    } catch (e) {
      _releaseLog('🎯 MANUAL MOVE FALLBACK: ERROR - $e');
      return;
    }
  }

  void _ensureNavigatorPointerSynced([ChessMovePointer? pointerOverride]) {
    if (_analysisNavigator == null || _analysisGame == null) {
      return;
    }
    final currentState = state.value;
    if (currentState == null) {
      return;
    }
    final targetPointer =
        pointerOverride ?? currentState.analysisState.movePointer;
    final navigatorState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    const pointerEquality = ListEquality<int>();
    if (!pointerEquality.equals(navigatorState.movePointer, targetPointer)) {
      _analysisNavigator!.goToMovePointerUnchecked(
        List<Number>.of(targetPointer),
      );
    }
  }

  void onAnalysisPromotionSelection(Role? role) {
    if (_analysisGame != null) {
      if (role == null) {
        state = AsyncValue.data(
          state.value!.copyWith(
            analysisState: state.value!.analysisState.copyWith(
              promotionMove: null,
            ),
          ),
        );
        HapticFeedback.selectionClick();
        return;
      }

      final pending = state.value?.analysisState.promotionMove;
      if (pending != null) {
        _releaseLog('🎯 PROMOTION SELECTION: Pending move UCI: ${pending.uci}');
        _releaseLog(
          '🎯 PROMOTION SELECTION: Pending from: ${pending.from}, to: ${pending.to}',
        );
        _releaseLog('🎯 PROMOTION SELECTION: Selected role: $role');

        final currentState = state.value!;
        final boardPosition = currentState.analysisState.position;
        final move = pending.withPromotion(role);

        _releaseLog(
          '🎯 PROMOTION SELECTION: Final move UCI with promotion: ${move.uci}',
        );
        _releaseLog('🎯 PROMOTION SELECTION: Board FEN: ${boardPosition.fen}');

        // Verify navigator is in sync before applying promotion
        if (_analysisNavigator != null) {
          final navigatorState = ref.read(
            chessGameNavigatorProvider(_analysisGame!),
          );
          _releaseLog(
            '🎯 PROMOTION SELECTION: Navigator FEN: ${navigatorState.currentFen}',
          );

          if (navigatorState.currentFen == boardPosition.fen) {
            _releaseLog(
              '🎯 PROMOTION SELECTION: Navigator in sync, applying via navigator',
            );
            const pointerEquality = ListEquality<int>();
            final boardPointer = currentState.analysisState.movePointer;
            _releaseLog(
              '🎯 POINTER SYNC CHECK: Board pointer=$boardPointer, Navigator pointer=${navigatorState.movePointer}',
            );
            if (!pointerEquality.equals(
              navigatorState.movePointer,
              boardPointer,
            )) {
              _releaseLog(
                '🎯 POINTER SYNC: Pointers differ, syncing navigator to board pointer=$boardPointer',
              );
              _analysisNavigator?.goToMovePointerUnchecked(boardPointer);
            } else {
              _releaseLog(
                '🎯 POINTER SYNC: Pointers already in sync at $boardPointer',
              );
            }
            _analysisNavigator?.makeOrGoToMove(move.uci);

            // Sync state after navigation
            final updatedState = ref.read(
              chessGameNavigatorProvider(_analysisGame!),
            );
            _syncAnalysisFromNavigator(updatedState);

            HapticFeedback.mediumImpact();
          } else {
            _releaseLog(
              '🎯 PROMOTION SELECTION: Navigator OUT OF SYNC, using manual fallback',
            );
            // Use manual application as fallback
            _applyManualAnalysisMove(currentState, boardPosition, move);
            HapticFeedback.mediumImpact();
          }
        } else {
          _releaseLog(
            '🎯 PROMOTION SELECTION: No navigator, using manual fallback',
          );
          _applyManualAnalysisMove(currentState, boardPosition, move);
          HapticFeedback.mediumImpact();
        }

        state = AsyncValue.data(
          state.value!.copyWith(
            analysisState: state.value!.analysisState.copyWith(
              promotionMove: null,
            ),
          ),
        );
      }
      return;
    }

    var currentState = state.value;
    if (currentState == null) return;
    if (role == null) {
      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            promotionMove: null,
          ),
        ),
      );
    }
  }

  /// Navigate forward in analysis mode (through main line when no variant selected)
  void analysisStepForward() {
    _releaseLog('🎯 ANALYSIS STEP FORWARD called');

    final currentState = state.value;
    if (currentState == null) return;

    // If preview mode is active, navigate within preview instead of exiting
    if (currentState.isPvPreviewActive) {
      _releaseLog(
        '🎯 ANALYSIS STEP FORWARD: Preview mode active, navigating in preview',
      );
      final currentNavIndex = currentState.lockedPvNavigationIndex ?? -1;
      final pvLength = currentState.lockedPvLine?.moves.length ?? 0;
      if (pvLength == 0) {
        return;
      }
      final nextIndex = currentNavIndex < 0 ? 0 : currentNavIndex + 1;
      if (nextIndex < pvLength) {
        _navigateToLockedPvIndex(nextIndex);
      }
      return;
    }

    _exitPvPreviewIfActive();
    if (state.value?.isAnalysisMode != true) {
      _releaseLog('🎯 ANALYSIS STEP FORWARD: Not in analysis mode');
      return;
    }
    if (_analysisGame == null) {
      _releaseLog('🎯 ANALYSIS STEP FORWARD: ERROR - _analysisGame is null');
      return;
    }
    if (_analysisNavigator == null) {
      _releaseLog(
        '🎯 ANALYSIS STEP FORWARD: ERROR - _analysisNavigator is null',
      );
      return;
    }

    if (currentState.selectedVariantIndex != null ||
        currentState.variantMovePointer.isNotEmpty) {
      state = AsyncValue.data(_clearVariantSelection(currentState));
    }

    // CRITICAL: Reset cancellation flag before navigation to ensure evaluation happens
    _cancelEvaluation = false;

    final navigatorState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    _releaseLog(
      '🎯 ANALYSIS STEP FORWARD: Current movePointer=${navigatorState.movePointer}',
    );
    _releaseLog(
      '🎯 ANALYSIS STEP FORWARD: Current FEN=${navigatorState.currentFen}',
    );
    _releaseLog('🎯 ANALYSIS STEP FORWARD: Calling goToNextMove on navigator');
    _analysisNavigator?.goToNextMove();

    // CRITICAL: Manually sync state after navigation to ensure board updates immediately.
    // The ref.listen callback may not fire synchronously, causing the notation to update
    // (it watches navigator directly) while the board state lags behind.
    final updatedState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    _syncAnalysisFromNavigator(updatedState);
  }

  /// Navigate backward in analysis mode (through main line when no variant selected)
  void analysisStepBackward() {
    _releaseLog('🎯 ANALYSIS STEP BACKWARD called');

    final currentState = state.value;
    if (currentState == null) return;

    // If preview mode is active, navigate within preview instead of exiting
    if (currentState.isPvPreviewActive) {
      _releaseLog(
        '🎯 ANALYSIS STEP BACKWARD: Preview mode active, navigating in preview',
      );
      final currentNavIndex = currentState.lockedPvNavigationIndex ?? -1;
      if (currentNavIndex > 0) {
        _navigateToLockedPvIndex(currentNavIndex - 1);
      } else if (currentNavIndex == -1) {
        _navigateToLockedPvIndex(0);
      }
      return;
    }

    _exitPvPreviewIfActive();
    if (state.value?.isAnalysisMode != true) {
      _releaseLog('🎯 ANALYSIS STEP BACKWARD: Not in analysis mode');
      return;
    }
    if (_analysisGame == null) {
      _releaseLog('🎯 ANALYSIS STEP BACKWARD: ERROR - _analysisGame is null');
      return;
    }
    if (_analysisNavigator == null) {
      _releaseLog(
        '🎯 ANALYSIS STEP BACKWARD: ERROR - _analysisNavigator is null',
      );
      return;
    }

    if (currentState.selectedVariantIndex != null ||
        currentState.variantMovePointer.isNotEmpty) {
      state = AsyncValue.data(_clearVariantSelection(currentState));
    }

    // CRITICAL: Reset cancellation flag before navigation to ensure evaluation happens
    _cancelEvaluation = false;

    final navigatorState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    _releaseLog(
      '🎯 ANALYSIS STEP BACKWARD: Current movePointer=${navigatorState.movePointer}',
    );
    _releaseLog(
      '🎯 ANALYSIS STEP BACKWARD: Current FEN=${navigatorState.currentFen}',
    );
    _releaseLog(
      '🎯 ANALYSIS STEP BACKWARD: Calling goToPreviousMove on navigator',
    );
    _analysisNavigator?.goToPreviousMove();

    // CRITICAL: Manually sync state after navigation to ensure board updates immediately.
    // The ref.listen callback may not fire synchronously, causing the notation to update
    // (it watches navigator directly) while the board state lags behind.
    final updatedState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    _syncAnalysisFromNavigator(updatedState);
  }

  void jumpToStart() {
    _releaseLog('🎯 JUMP TO START called');
    _exitPvPreviewIfActive();
    final currentState = state.value;
    if (currentState == null) return;

    if (currentState.isAnalysisMode) {
      // Check if variant is selected
      if (currentState.selectedVariantIndex != null) {
        _releaseLog(
          '🎯 JUMP TO START: Variant selected, jumping to variant start',
        );
        // Jump to start of variant (root position)
        final currentMoveIndex = currentState.currentMoveIndex;
        final rootPointer =
            currentMoveIndex < 0 ? const <int>[] : [currentMoveIndex];
        _analysisNavigator?.goToMovePointerUnchecked(rootPointer);

        // Reset variant move pointer
        state = AsyncValue.data(
          currentState.copyWith(variantMovePointer: const []),
        );
      } else {
        _releaseLog('🎯 JUMP TO START: No variant, jumping to game start');
        _analysisNavigator?.goToHead();
      }

      // Sync state after navigation
      if (_analysisGame != null) {
        final updatedState = ref.read(
          chessGameNavigatorProvider(_analysisGame!),
        );
        _syncAnalysisFromNavigator(updatedState);
      }
    } else {
      goToMove(-1);
    }
  }

  void jumpToEnd() {
    _releaseLog('🎯 JUMP TO END called');
    final currentState = state.value;
    if (currentState == null) return;

    if (currentState.isAnalysisMode) {
      // Check if variant is selected
      if (currentState.selectedVariantIndex != null) {
        _releaseLog(
          '🎯 JUMP TO END: Variant selected, playing all variant moves',
        );
        final selectedVariant =
            currentState.principalVariations[currentState
                .selectedVariantIndex!];
        final totalMoves = selectedVariant.moves.length;
        final currentProgress = currentState.variantMovePointer.length;

        _releaseLog(
          '🎯 JUMP TO END: totalMoves=$totalMoves, currentProgress=$currentProgress',
        );

        // Play all remaining moves in the variant
        for (int i = currentProgress; i < totalMoves; i++) {
          final move = selectedVariant.moves[i];
          if (move is NormalMove && !isPromotionPawnMove(move)) {
            _analysisNavigator?.makeOrGoToMove(move.uci);
          }
        }

        // Update variant move pointer to the end
        state = AsyncValue.data(
          currentState.copyWith(
            variantMovePointer: List.generate(totalMoves, (index) => index),
          ),
        );
      } else {
        _releaseLog('🎯 JUMP TO END: No variant, jumping to game end');
        _analysisNavigator?.goToTail();
      }

      // Sync state after navigation
      if (_analysisGame != null) {
        final updatedState = ref.read(
          chessGameNavigatorProvider(_analysisGame!),
        );
        _syncAnalysisFromNavigator(updatedState);
      }
    } else {
      goToMove(currentState.allMoves.length - 1);
    }
  }

  void resetGame() {
    _exitPvPreviewIfActive();
    if (state.value?.isAnalysisMode == true) {
      _analysisNavigator?.goToHead();

      // Sync state after navigation
      if (_analysisGame != null) {
        final updatedState = ref.read(
          chessGameNavigatorProvider(_analysisGame!),
        );
        _syncAnalysisFromNavigator(updatedState);
      }
    } else {
      jumpToStart();
    }
  }

  void flipBoard() {
    final currentState = state.value;
    if (currentState == null) return;
    state = AsyncValue.data(
      currentState.copyWith(isBoardFlipped: !currentState.isBoardFlipped),
    );
    _scheduleAutoSave();
  }

  void updatePlayerName({required bool isWhite, required String newName}) {
    final currentState = state.value;
    if (currentState == null) return;
    final updatedGame =
        isWhite
            ? currentState.game.copyWith(
              whitePlayer: currentState.game.whitePlayer.copyWith(
                name: newName,
              ),
            )
            : currentState.game.copyWith(
              blackPlayer: currentState.game.blackPlayer.copyWith(
                name: newName,
              ),
            );
    state = AsyncValue.data(currentState.copyWith(game: updatedGame));
  }

  void toggleEngineVisibility() {
    final currentState = state.value;
    if (currentState == null) return;

    final newValue = !currentState.showEngineAnalysis;

    debugPrint(
      '🎯 ChessBoard[$index]: Toggling engine visibility: ${currentState.showEngineAnalysis} → $newValue',
    );

    // Update local state immediately for responsive UI
    state = AsyncValue.data(
      currentState.copyWith(
        showEngineAnalysis: newValue,
        showPrincipalVariations: newValue, // Keep in sync
      ),
    );

    // Persist to settings in background (unawaited, fire-and-forget)
    debugPrint(
      '🎯 ChessBoard[$index]: Persisting engine visibility to settings: $newValue',
    );
    // Use unawaited to truly fire-and-forget without blocking UI
    unawaited(
      ref
          .read(engineSettingsProviderNew.notifier)
          .toggleEngineAnalysis(newValue),
    );
  }

  void togglePlayPause() {
    final currentState = state.value;
    if (currentState == null) return;
    state = AsyncValue.data(
      currentState.copyWith(isPlaying: !currentState.isPlaying),
    );
  }

  void pauseGame() {
    final currentState = state.value;
    if (currentState == null || !currentState.isPlaying) return;
    state = AsyncValue.data(currentState.copyWith(isPlaying: false));
  }

  Future<void> onBecameInvisible() async {
    EasyDebounce.cancel('evaluation-$index');
    _cancelEvaluation = true;
    _cancelEvalWatchdog(resetPending: true);
    _clearActiveEvalState();
    // Cancel only THIS provider's Stockfish jobs, not all jobs globally
    await StockfishSingleton().cancelEvaluationsForOwner(_stockfishOwnerId);
    // Do NOT reset _cancelEvaluation here — keep it true so async retry
    // callbacks (.then, Future.microtask) that fire after cancellation see
    // the flag and bail out. onBecameVisible() resets it when the board
    // is actually visible again.
  }

  Future<void> onBecameVisible({bool force = true}) async {
    EasyDebounce.cancel('evaluation-$index');

    final stockfish = StockfishSingleton();
    final currentState = state.value;
    final currentPosition =
        currentState?.isAnalysisMode == true
            ? currentState!.analysisState.position
            : currentState?.position;
    final currentFen = currentPosition?.fen;
    final activeFen =
        currentFen == null
            ? null
            : (currentState?.isThreatsMode == true
                ? _getThreatFen(currentFen)
                : currentFen);
    final activeCacheKey =
        activeFen == null
            ? null
            : _fenCacheKey(activeFen, multiPV: _currentMultiPvSetting());
    final alreadyEvaluatingCurrentFen =
        !force &&
        currentState != null &&
        currentState.isEvaluating &&
        activeCacheKey != null &&
        _activeEvalRequestId != null &&
        _activeEvalKey == activeCacheKey;

    // If an evaluation is already active for the currently visible FEN,
    // avoid cancelling and restarting it. This prevents depth jitter/resets
    // from duplicate visibility callbacks.
    if (alreadyEvaluatingCurrentFen && !stockfish.requiresRecovery) {
      _cancelEvaluation = false;
      if (activeFen != null) {
        _registerPendingEvaluation(activeFen);
      }
      return;
    }

    // Cancel only THIS provider's stale jobs before starting new evaluation
    await stockfish.cancelEvaluationsForOwner(_stockfishOwnerId);

    // Recover engine when lifecycle transitions leave it in a bad state.
    if (stockfish.requiresRecovery) {
      _releaseLog(
        '🔧 LIFECYCLE: Recovering Stockfish (state: ${stockfish.engineStateDebug})',
      );
      try {
        await stockfish.forceRecovery();
      } catch (e) {
        _releaseLog('⚠️ LIFECYCLE: Stockfish recovery failed: $e');
      }
    }

    _cancelEvaluation = false;
    _cancelEvalWatchdog(resetPending: true);
    _clearActiveEvalState();
    _updateEvaluation(force: force);
  }

  Color getMoveColor(String move, int moveIndex) {
    final currentState = state.value!;
    if (currentState.isLoadingMoves) {
      return kWhiteColor.withValues(alpha: 0.3);
    }

    final referenceIndex =
        currentState.isAnalysisMode
            ? currentState.analysisState.currentMoveIndex
            : currentState.currentMoveIndex;

    if (referenceIndex >= 0 && moveIndex <= referenceIndex) {
      return kWhiteColor;
    }

    return kWhiteColor70;
  }

  String _getSamplePgnData() {
    return '''
[Event "Round 3: Binks, Michael - Hardman, Michael J"]
[Site "?"]
[Date "????.??.??"]
[Round "3.3"]
[White "Binks, Michael"]
[Black "Hardman, Michael J"]
[Result "0-1"]
[WhiteElo "1894"]
[WhiteFideId "1800957"]
[BlackElo "2057"]
[BlackFideId "409324"]
[Variant "Standard"]
[ECO "A55"]
[Opening "Old Indian Defense: Normal Variation"]

1. d4 d6 2. Nf3 Nf6 3. c4 Nbd7 4. Nc3 e5 5. e4 c6 6. Be2 Be7 7. O-O Qc7 8. h3 O-O 9. Be3 Re8 10. Rc1 exd4 11. Nxd4 Nc5 12. Qc2 a5 13. f4 Bf8 14. Bf3 g6 15. Nde2 Ncxe4 16. Nxe4 Nxe4 17. Bxe4 Qe7 18. Ng3 d5 19. cxd5 cxd5 20. Bxd5 Qxe3+ 21. Qf2 Qxf2+ 22. Kxf2 Be6 23. Bxe6 Rxe6 24. Rfd1 b6 25. Kf3 Rae8 26. Rc4 Re3+ 27. Kf2 Bc5 28. Rxc5 bxc5 29. Rc1 Rd3 30. Rc2 Kg7 31. Nf1 Re4 32. g3 Rb4 33. b3 a4 34. Rxc5 axb3 35. axb3 Rbxb3 36. Rc2 h5 37. h4 Rf3+ 38. Kg2 Rfc3 39. Re2 Rc5 40. Kf2 Rcb5 41. Re8 Rb2+ 42. Kf3 R5b3+ 43. Ne3 Ra2 44. Re7 Rbb2 45. g4 hxg4+ 46. Nxg4 Ra3+ 47. Ne3 Kf8 48. Re4 f6 49. Kg3 Kf7 50. Kf3 Rh2 51. Kg3 Rh1 52. Kg2 Rxh4 53. Nd5 Ra7 0-1
''';
  }

  String _buildFenFallbackPgn(String rawFen) {
    final safeFen = rawFen.trim();
    String sanitize(String value) => value.replaceAll('"', "'");
    final whiteName = sanitize(game.whitePlayer.name);
    final blackName = sanitize(game.blackPlayer.name);
    final eventName = sanitize(game.roundSlug ?? game.roundId);
    final siteName = sanitize(game.tourSlug ?? game.tourId);

    return '''
[Event "$eventName"]
[Site "$siteName"]
[White "$whiteName"]
[Black "$blackName"]
[SetUp "1"]
[FEN "$safeFen"]

*
''';
  }

  Future<List<AnalysisLine>> _buildPrincipalVariations(
    String fen,
    List<Pv> pvs,
  ) async {
    if (pvs.isEmpty) {
      _releaseLog('⚠️ BUILD PV: Empty PVs list provided');
      return const [];
    }

    // Filter out PVs with empty or invalid moves BEFORE validation
    // This prevents cloud cache pollution from breaking the entire cascade
    final validPvs = pvs.where((pv) => pv.moves.trim().isNotEmpty).toList();
    if (validPvs.isEmpty) {
      _releaseLog(
        '⚠️ BUILD PV: All PVs have empty moves - likely stale cloud cache',
      );
      return const [];
    }

    // TEMPO-01-COMMENT
    // _releaseLog(
    //   '🎯 BUILD PV: Starting with ${validPvs.length} valid PVs (filtered ${pvs.length - validPvs.length} empty) for $fen',
    // );

    // OPTIMIZATION: Skip validation check - worker will filter out invalid moves
    // The validation was making PV cards load slowly by doing upfront position creation
    // If worker returns empty, we'll handle it gracefully below
    final limitedPvs = validPvs;
    final payload = {
      'fen': fen,
      'pvs':
          limitedPvs
              .map(
                (pv) => {
                  'moves': pv.moves,
                  'cp': pv.cp,
                  'isMate': pv.isMate,
                  'mate': pv.mate,
                },
              )
              .toList(),
    };

    // Run analysis on main thread - the calculation is lightweight
    final workerResult = _analysisLinesWorker(payload);
    if (workerResult.isEmpty) {
      _releaseLog('❌ BUILD PV: Analysis returned empty result');
      return const [];
    }

    final lines = <AnalysisLine>[];
    for (final entry in workerResult) {
      final uciMoves =
          (entry['uci'] as List<dynamic>? ?? const []).cast<String>();
      final sanMoves =
          (entry['san'] as List<dynamic>? ?? const []).cast<String>();
      final bool isMate = entry['isMate'] == true;
      final mateValue = entry['mate'];
      final cpValue = entry['cp'];

      // Parse UCI → Move directly; the worker already validated every move
      // via position.makeSan(), so skip the expensive position.play() loop.
      final moves = <Move>[];
      var valid = true;

      for (final uci in uciMoves) {
        if (uci.isEmpty) continue;
        final parsedMove = Move.parse(uci);
        if (parsedMove == null) {
          valid = false;
          break;
        }
        moves.add(parsedMove);
      }

      if (!valid || moves.isEmpty) continue;

      double? evaluation;
      int? mate;

      if (isMate) {
        mate =
            mateValue is int
                ? mateValue
                : int.tryParse(mateValue?.toString() ?? '');
        mate = _getConsistentMate(mate, fen);
      } else {
        final cp =
            cpValue is int
                ? cpValue
                : int.tryParse(cpValue?.toString() ?? '0') ?? 0;
        evaluation = _getConsistentEvaluation(cp / 100.0, fen);
      }

      lines.add(
        AnalysisLine(
          moves: moves,
          sanMoves: sanMoves,
          evaluation: evaluation,
          mate: mate,
        ),
      );
    }

    // TEMPO-01-COMMENT
    // _releaseLog(
    //   '🎯 BUILD PV: Successfully built ${lines.length} analysis lines',
    // );
    if (lines.isEmpty) {
      _releaseLog(
        '❌ BUILD PV: No valid lines could be built from ${workerResult.length} worker results',
      );
    }

    // Return actual variations without padding
    // UI will handle displaying 1-3 PV cards dynamically
    // TEMPO-01-COMMENT
    // _releaseLog(
    //   '✅ BUILD PV: Returning ${lines.length} principal variations (no padding)',
    // );

    return lines;
  }

  List<AnalysisLine> _mergePvProgress(
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
      if (prevMoves.length > newMoves.length &&
          _isPrefixMoves(newMoves, prevMoves)) {
        merged.add(prevLine);
      } else {
        merged.add(newLine);
      }
    }
    return merged;
  }

  bool _isPrefixMoves(List<Move> shorter, List<Move> longer) {
    if (shorter.length > longer.length) return false;
    for (var i = 0; i < shorter.length; i++) {
      if (shorter[i].uci != longer[i].uci) return false;
    }
    return true;
  }

  ChessGameNavigator? get _analysisNavigator =>
      _analysisGame == null
          ? null
          : ref.read(chessGameNavigatorProvider(_analysisGame!).notifier);

  bool _canAnalysisNavigatorMoveForward() {
    if (_analysisGame == null) return false;
    final navigatorState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    return navigatorState.canGoForward;
  }

  bool _canAnalysisNavigatorMoveBackward() {
    if (_analysisGame == null) return false;
    final navigatorState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    return navigatorState.canGoBackward;
  }

  void _exitPvPreviewIfActive() {
    if (_pvPreviewSnapshot == null && state.value?.isPvPreviewActive != true) {
      return;
    }
    final currentState = state.value;
    if (currentState == null) {
      _pvPreviewSnapshot = null;
      return;
    }
    final snapshot = _pvPreviewSnapshot ?? currentState;
    _pvPreviewSnapshot = null;

    // Check if position is changing when exiting preview
    final currentFen = currentState.analysisState.position.fen;
    final snapshotFen = snapshot.analysisState.position.fen;
    final positionChanged = currentFen != snapshotFen;

    state = AsyncValue.data(
      currentState.copyWith(
        analysisState: snapshot.analysisState,
        evaluation: snapshot.evaluation,
        mate: snapshot.mate,
        shapes: snapshot.shapes,
        isPvPreviewActive: false,
        pvPreviewVariantIndex: null,
        pvPreviewMoveIndex: null,
        lockedPvLine: null,
        lockedPvMergedMoves: null,
        lockedPvMergedMoveObjects: null,
        lockedPvMergedPositions: null,
        lockedPvBaseMoveCount: null,
        lockedPvNavigationIndex: null,
        // CRITICAL: Preserve isEvaluating state to show continued progress
        isEvaluating: positionChanged ? true : currentState.isEvaluating,
      ),
    );

    // CRITICAL: Only force new evaluation if position changed
    // If returning to same position, let ongoing evaluation continue without interference
    if (positionChanged) {
      _updateEvaluation(
        force: true,
        preserveCurrentPvs: true,
        preserveDepthProgress: true,
      );
    }
    // If position unchanged, don't call _updateEvaluation at all
    // Let the ongoing background evaluation continue uninterrupted
  }

  bool _isEditingBlockedByPreview({String? reason}) {
    final currentState = state.value;
    if (currentState?.isPvPreviewActive == true) {
      final description = reason != null ? ' ($reason)' : '';
      _releaseLog(
        '🚫 PREVIEW BLOCK: Edit attempt while preview is active$description',
      );
      HapticFeedback.mediumImpact();
      return true;
    }
    return false;
  }

  void _playSoundForSan(String san) {
    // Check if sound is enabled in user settings
    final boardSettings = ref.read(boardSettingsProviderNew).valueOrNull;
    if (boardSettings?.soundEnabled != true) {
      return; // Sound disabled, skip playing
    }

    AudioPlayerService.instance.playSfxForSan(san);
  }

  bool _ensureVariantSelection() {
    final currentState = state.value;
    if (currentState == null || !currentState.isAnalysisMode) {
      return false;
    }
    if (currentState.principalVariations.isEmpty) {
      return false;
    }
    if (currentState.selectedVariantIndex != null) {
      return true;
    }
    selectVariant(0);
    return true;
  }

  /// Validates if variant navigation is safe from the current position
  /// Returns false if the variant base FEN is stale or unreachable
  bool _isVariantNavigationValid(ChessBoardStateNew state) {
    if (state.variantBaseFen == null) {
      _releaseLog('🎯 VARIANT VALIDATION: No variant base FEN');
      return false;
    }
    if (state.selectedVariantIndex == null) {
      _releaseLog('🎯 VARIANT VALIDATION: No variant selected');
      return false;
    }
    if (state.selectedVariantIndex! >= state.principalVariations.length) {
      _releaseLog('🎯 VARIANT VALIDATION: Invalid variant index');
      return false;
    }

    final currentFen = state.analysisState.position.fen;
    final baseFen = state.variantBaseFen!;

    // Compare first 3 FEN components (position, turn, castling)
    final currentParts = currentFen.split(' ').take(3).join(' ');
    final baseParts = baseFen.split(' ').take(3).join(' ');

    // If we're at the base position, it's valid
    if (currentParts == baseParts) {
      _releaseLog('🎯 VARIANT VALIDATION: At base position - VALID');
      return true;
    }

    // If we've applied variant moves from base, verify the position is reachable
    if (state.variantMovePointer.isNotEmpty) {
      try {
        final selectedVariant =
            state.principalVariations[state.selectedVariantIndex!];
        final testPosition = _variantPositionFromBase(
          state,
          selectedVariant,
          state.variantMovePointer.length,
        );
        final matches =
            testPosition.fen.split(' ').take(3).join(' ') == currentParts;
        _releaseLog(
          '🎯 VARIANT VALIDATION: Position reachable from base - ${matches ? "VALID" : "INVALID"}',
        );
        return matches;
      } catch (e) {
        _releaseLog('🎯 VARIANT VALIDATION: ERROR calculating position: $e');
        return false;
      }
    }

    // CRITICAL FIX: If pointer is empty, we MUST be at the base position
    // If we're not at base and pointer is empty, the variant base is stale
    // This means PVs were recalculated for a new position
    _releaseLog(
      '🎯 VARIANT VALIDATION: Position mismatch with empty pointer - base FEN is stale, INVALID',
    );
    return false;
  }

  ChessBoardStateNew _clearVariantSelection(ChessBoardStateNew stateToUpdate) {
    _resumeVariantAutoPlay = false;
    if (stateToUpdate.selectedVariantIndex == null &&
        stateToUpdate.variantMovePointer.isEmpty &&
        stateToUpdate.variantBaseFen == null) {
      return stateToUpdate;
    }

    return stateToUpdate.copyWith(
      selectedVariantIndex: null,
      variantMovePointer: const [],
      variantBaseFen: null,
      variantBaseMovePointer: null,
      variantBaseLastMove: null,
      variantBaseMoveIndex: null,
    );
  }

  ChessBoardStateNew _rebaseVariantAfterCommittedMove({
    required ChessBoardStateNew currentState,
    required int committedMoveIndex,
    required Position positionAfterMove,
    required Move committedMove,
  }) {
    final selectedIndex = currentState.selectedVariantIndex;
    if (selectedIndex == null ||
        selectedIndex >= currentState.principalVariations.length) {
      return _clearVariantSelection(
        currentState.copyWith(
          principalVariations: const [],
          principalVariationsBaseFen: positionAfterMove.fen,
          analysisState: currentState.analysisState.copyWith(
            suggestionLines: const [],
            position: positionAfterMove,
            lastMove: committedMove,
            validMoves: makeLegalMoves(positionAfterMove),
            currentMoveIndex: currentState.analysisState.currentMoveIndex + 1,
          ),
        ),
      );
    }

    final variant = currentState.principalVariations[selectedIndex];
    final continuationStart = committedMoveIndex + 1;
    if (continuationStart >= variant.moves.length) {
      return _clearVariantSelection(
        currentState.copyWith(
          principalVariations: const [],
          principalVariationsBaseFen: positionAfterMove.fen,
          analysisState: currentState.analysisState.copyWith(
            suggestionLines: const [],
            position: positionAfterMove,
            lastMove: committedMove,
            validMoves: makeLegalMoves(positionAfterMove),
            currentMoveIndex: currentState.analysisState.currentMoveIndex + 1,
          ),
        ),
      );
    }

    final trimmedVariant = variant.copyWith(
      moves: variant.moves.sublist(continuationStart),
      sanMoves: variant.sanMoves.sublist(continuationStart),
    );
    final rebasedLines = <AnalysisLine>[trimmedVariant];
    final arrowShapes = _maybeSuppressShapes(
      currentState,
      _getAllVariantArrowShapes(
        rebasedLines,
        0,
        isThreatsMode: currentState.isThreatsMode,
      ),
    );

    final updatedAnalysis = currentState.analysisState.copyWith(
      position: positionAfterMove,
      lastMove: committedMove,
      validMoves: makeLegalMoves(positionAfterMove),
      currentMoveIndex: currentState.analysisState.currentMoveIndex + 1,
      suggestionLines: rebasedLines,
    );

    return currentState.copyWith(
      principalVariations: rebasedLines,
      principalVariationsBaseFen: positionAfterMove.fen,
      analysisState: updatedAnalysis,
      selectedVariantIndex: 0,
      variantMovePointer: const [],
      variantBaseFen: positionAfterMove.fen,
      variantBaseMovePointer: currentState.analysisState.movePointer,
      variantBaseLastMove: committedMove,
      variantBaseMoveIndex: currentState.analysisState.currentMoveIndex + 1,
      shapes: arrowShapes,
    );
  }

  ChessBoardStateNew _setVariantProgress({
    required ChessBoardStateNew currentState,
    required Position currentPosition,
  }) {
    final selectedIndex = currentState.selectedVariantIndex;
    final baseFen = currentState.variantBaseFen;

    if (selectedIndex == null || baseFen == null) {
      return currentState;
    }

    if (selectedIndex >= currentState.principalVariations.length) {
      return _clearVariantSelection(currentState);
    }

    final variant = currentState.principalVariations[selectedIndex];
    if (variant.moves.isEmpty) {
      return _clearVariantSelection(currentState);
    }

    final progress = _calculateVariantProgress(
      baseFen,
      variant.moves,
      currentPosition.fen,
      isThreatsMode: currentState.isThreatsMode,
    );

    if (progress < 0) {
      return _clearVariantSelection(currentState);
    }

    final pointer = List<int>.generate(progress, (index) => index);
    return currentState.copyWith(variantMovePointer: pointer);
  }

  void _applyPrincipalVariationResults({
    required ChessBoardStateNew currentState,
    required Position currentPosition,
    required String baseFen,
    required ChessMovePointer? baseMovePointer,
    required List<AnalysisLine> pvLines,
  }) {
    final previousSelection = currentState.selectedVariantIndex;
    final previousBaseFen = currentState.variantBaseFen;
    final previousVariantPointer = currentState.variantMovePointer;
    final shouldResumeAutoPlay = _resumeVariantAutoPlay;

    // CRITICAL: Validate PVs match the variant base FEN
    // BUT: Allow PV updates during extension (when pointer is empty and we're resuming)
    // Extension means we updated the base to current position and reset pointer to []
    final isExtensionUpdate =
        previousVariantPointer.isEmpty && shouldResumeAutoPlay;

    if (previousSelection != null &&
        previousBaseFen != null &&
        !isExtensionUpdate) {
      // Only validate if NOT an extension update
      final baseFenCompare = previousBaseFen.split(' ').take(3).join(' ');
      final pvFenCompare = baseFen.split(' ').take(3).join(' ');

      if (baseFenCompare != pvFenCompare) {
        _releaseLog('❌ PV APPLY: REJECTED - FEN mismatch');
        _releaseLog('   Current base: $baseFenCompare');
        _releaseLog('   PV from: $pvFenCompare');
        _releaseLog('   Lines: ${pvLines.length}');
        // Keep current state, don't apply these PVs
        return;
      }
      // TEMPO-01-COMMENT
      // _releaseLog(
      //   '✅ PV APPLY: FEN match confirmed, applying ${pvLines.length} lines',
      // );
    } else {
      // TEMPO-01-COMMENT
      // _releaseLog(
      //   '✅ PV APPLY: No validation needed (new selection or extension), applying ${pvLines.length} lines',
      // );
    }

    // CRITICAL: Preserve evaluation, mate, and isEvaluating from currentState
    // The caller already set these values and we must NOT reset them
    var nextState = currentState.copyWith(
      principalVariations: pvLines,
      principalVariationsBaseFen: baseFen,
      analysisState: currentState.analysisState.copyWith(
        suggestionLines: pvLines,
      ),
      // Explicitly preserve evaluation state
      evaluation: currentState.evaluation,
      mate: currentState.mate,
      isEvaluating: currentState.isEvaluating,
    );

    final bool shouldDefaultSelect =
        previousSelection == null &&
        pvLines.isNotEmpty &&
        currentState.isAnalysisMode;

    // CRITICAL FIX: Check if we're in middle of variant exploration
    final bool inVariantExploration =
        previousSelection != null &&
        previousVariantPointer.isNotEmpty &&
        previousBaseFen != null;

    if (shouldDefaultSelect) {
      // New variant selection - lock current position as base
      final arrowShapes = _maybeSuppressShapes(
        nextState,
        _getAllVariantArrowShapes(
          pvLines,
          0,
          isThreatsMode: currentState.isThreatsMode,
        ),
      );
      nextState = nextState.copyWith(
        selectedVariantIndex: 0,
        variantBaseFen: baseFen,
        variantBaseMovePointer: baseMovePointer,
        variantBaseLastMove: currentState.analysisState.lastMove,
        variantBaseMoveIndex: currentState.analysisState.currentMoveIndex,
        variantMovePointer: const [],
        shapes: arrowShapes,
      );
    } else if (previousSelection != null &&
        previousSelection < pvLines.length &&
        currentState.isAnalysisMode) {
      // Variant was already selected

      if (inVariantExploration) {
        // CRITICAL: We're exploring a variant
        // ALWAYS keep the original locked base - even if current position changed
        // TEMPO-01-COMMENT
        // _releaseLog(
        //   '🎯 PV RESULTS: Preserving locked base FEN during variant exploration',
        // );
        final arrowShapes = _getAllVariantArrowShapes(
          pvLines,
          previousSelection,
          isThreatsMode: currentState.isThreatsMode,
        );
        nextState = nextState.copyWith(
          selectedVariantIndex: previousSelection,
          // Keep the ORIGINAL base FEN, don't update it!
          variantBaseFen: previousBaseFen,
          variantBaseMovePointer: currentState.variantBaseMovePointer,
          variantBaseLastMove: currentState.variantBaseLastMove,
          variantBaseMoveIndex: currentState.variantBaseMoveIndex,
          variantMovePointer: previousVariantPointer,
          shapes: _maybeSuppressShapes(nextState, arrowShapes),
        );
      } else {
        // Not in variant exploration - safe to update base
        // TEMPO-01-COMMENT
        // _releaseLog(
        //   '🎯 PV RESULTS: Not in variant exploration, updating base FEN',
        // );

        // CRITICAL: Validate the selected variant is still valid for the new base
        // The variant index might be the same, but the actual variant is different now
        final newSelectedVariant = pvLines[previousSelection];
        bool variantIsValid = true;

        if (newSelectedVariant.moves.isNotEmpty) {
          try {
            // Try to apply the first move from the new base position
            final testPosition = Position.setupPosition(
              Rule.chess,
              Setup.parseFen(baseFen),
            );
            testPosition.play(newSelectedVariant.moves.first);
          } catch (e) {
            _releaseLog(
              '🎯 PV RESULTS: Selected variant no longer valid for new base position',
            );
            _releaseLog('   Old base: $previousBaseFen');
            _releaseLog('   New base: $baseFen');
            _releaseLog('   First move: ${newSelectedVariant.moves.first.uci}');
            variantIsValid = false;
          }
        }

        if (variantIsValid) {
          final arrowShapes = _getAllVariantArrowShapes(
            pvLines,
            previousSelection,
            isThreatsMode: currentState.isThreatsMode,
          );
          nextState = nextState.copyWith(
            selectedVariantIndex: previousSelection,
            variantBaseFen: baseFen,
            variantBaseMovePointer: baseMovePointer,
            variantBaseLastMove: currentState.analysisState.lastMove,
            variantBaseMoveIndex: currentState.analysisState.currentMoveIndex,
            variantMovePointer: const [],
            shapes: _maybeSuppressShapes(nextState, arrowShapes),
          );
        } else {
          // Variant is invalid, clear selection
          _releaseLog('🎯 PV RESULTS: Clearing invalid variant selection');
          nextState = _clearVariantSelection(nextState);
        }
      }
    } else {
      // No variant selected - but if in preview mode, still show PV arrows
      if (currentState.isPvPreviewActive && pvLines.isNotEmpty) {
        final arrowShapes = _getAllVariantArrowShapes(
          pvLines,
          0,
          isThreatsMode: currentState.isThreatsMode,
        );
        nextState = nextState.copyWith(
          shapes: _maybeSuppressShapes(nextState, arrowShapes),
        );
      } else {
        nextState = _clearVariantSelection(nextState);
      }
    }

    _resumeVariantAutoPlay = false;
    state = AsyncValue.data(nextState);

    // CRITICAL FIX: Auto-resume variant playback if we were waiting for extension
    if (shouldResumeAutoPlay &&
        nextState.selectedVariantIndex != null &&
        nextState.selectedVariantIndex! < pvLines.length) {
      final newVariant = pvLines[nextState.selectedVariantIndex!];

      _releaseLog(
        '🎯 AUTO-RESUME: Extension completed, newVariantLength=${newVariant.moves.length}',
      );

      // After extension, variantMovePointer was reset to []
      // and variantBaseFen was updated to current position
      // So we can start playing from index 0 of the new variant
      if (newVariant.moves.isNotEmpty) {
        _releaseLog(
          '🎯 AUTO-RESUME: New PVs available, resuming playback from new base',
        );
        // Use Future.microtask to avoid calling during build
        Future.microtask(() {
          if (mounted && state.value?.selectedVariantIndex != null) {
            playVariantMoveForward();
          }
        });
      } else {
        _releaseLog(
          '🎯 AUTO-RESUME: No moves in extended variant - game may be over',
        );
      }
    }
  }

  int _calculateVariantProgress(
    String baseFen,
    List<Move> moves,
    String currentFen, {
    bool isThreatsMode = false,
  }) {
    try {
      final effectiveBaseFen = isThreatsMode ? _getThreatFen(baseFen) : baseFen;
      final effectiveCurrentFen =
          isThreatsMode ? _getThreatFen(currentFen) : currentFen;

      var position = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(effectiveBaseFen),
      );
      if (position.fen == effectiveCurrentFen) return 0;

      for (int i = 0; i < moves.length; i++) {
        position = position.play(moves[i]);
        if (position.fen == effectiveCurrentFen) {
          return i + 1;
        }
      }
    } catch (_) {
      return -1;
    }
    return -1;
  }

  Position _variantPositionFromBase(
    ChessBoardStateNew state,
    AnalysisLine variant,
    int movesToApply,
  ) {
    final baseFen = state.variantBaseFen ?? state.analysisState.position.fen;
    final effectiveBaseFen =
        state.isThreatsMode ? _getThreatFen(baseFen) : baseFen;
    var position = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(effectiveBaseFen),
    );

    for (int i = 0; i < movesToApply && i < variant.moves.length; i++) {
      position = position.play(variant.moves[i]);
    }

    return position;
  }

  Future<void> _evaluatePosition({
    bool force = false,
    bool preserveCurrentPvs = false,
    bool preserveDepthProgress = false,
    bool skipPvUpdates = false,
  }) async {
    int? requestId;
    String? lastEvaluatedFen;
    try {
      final initialState = state.value;
      if (initialState == null || initialState.isLoadingMoves) {
        // CRITICAL FIX: Clear evaluating state on early return
        if (initialState != null && initialState.isEvaluating) {
          state = AsyncValue.data(initialState.copyWith(isEvaluating: false));
        }
        return;
      }

      final previewActive = initialState.isPvPreviewActive;
      final effectiveSkipPv = skipPvUpdates || previewActive;
      final currentFenForState =
          initialState.isAnalysisMode
              ? initialState.analysisState.position.fen
              : initialState.position?.fen;
      final sameFenAsActiveEval =
          currentFenForState != null &&
          _activeEvalKey != null &&
          _fenCacheKey(
                initialState.isThreatsMode
                    ? _getThreatFen(currentFenForState)
                    : currentFenForState,
                multiPV: _currentMultiPvSetting(),
              ) ==
              _activeEvalKey;
      final keepPvs =
          preserveCurrentPvs ||
          effectiveSkipPv ||
          (sameFenAsActiveEval && initialState.principalVariations.isNotEmpty);
      final keepDepth =
          preserveDepthProgress ||
          previewActive ||
          (sameFenAsActiveEval && initialState.isEvaluating);

      // CRITICAL: Skip evaluation entirely if this is not the currently visible game
      // This prevents resource-intensive Stockfish analysis from running for off-screen games
      final currentVisiblePage = ref.read(currentlyVisiblePageIndexProvider);
      if (index != currentVisiblePage && !force) {
        _releaseLog(
          '🚫 EVAL: Skipping evaluation for non-visible game (page $index, visible: $currentVisiblePage)',
        );
        // Clear evaluating state if it was set
        if (initialState.isEvaluating) {
          state = AsyncValue.data(initialState.copyWith(isEvaluating: false));
        }
        return;
      }

      final Position? currentPosition =
          initialState.isAnalysisMode
              ? initialState.analysisState.position
              : initialState.position;
      final fen = currentPosition?.fen;
      if (fen == null) {
        // CRITICAL FIX: Clear evaluating state on early return
        state = AsyncValue.data(initialState.copyWith(isEvaluating: false));
        return;
      }

      // In threats mode, analyze from opponent's perspective
      final isThreatsMode = initialState.isThreatsMode;
      final fenToAnalyze = isThreatsMode ? _getThreatFen(fen) : fen;
      final Position positionForAnalysis =
          isThreatsMode
              ? Position.setupPosition(Rule.chess, Setup.parseFen(fenToAnalyze))
              : currentPosition!;

      if (isThreatsMode) {
        _releaseLog(
          '🎯 THREATS MODE: Analyzing opponent threats for position: $fen',
        );
        _releaseLog('   Threat FEN: $fenToAnalyze');
      }

      lastEvaluatedFen = fen;

      // Get engine settings FIRST to get configured PV count for cache key
      final engineSettingsAsync = ref.read(engineSettingsProviderNew);
      final engineSettings = engineSettingsAsync.value;
      final effectiveEngineSettings = engineSettings ?? const EngineSettings();
      final configuredMultiPV = effectiveEngineSettings.multiPvForStockfish();

      // Determine dynamic Stockfish search profile from engine settings
      final gaugeDuration = effectiveEngineSettings.searchDurationFor(
        EngineComponent.evaluationGauge,
      );
      final pvDuration = effectiveEngineSettings.searchDurationFor(
        EngineComponent.principalVariation,
      );

      Duration? combinedSearchDuration;
      if (gaugeDuration == null || pvDuration == null) {
        // Any null duration indicates "infinite" search, so allow engine to run freely
        combinedSearchDuration = null;
      } else {
        combinedSearchDuration =
            gaugeDuration >= pvDuration ? gaugeDuration : pvDuration;
        const fallbackCap = Duration(seconds: 10);
        if (combinedSearchDuration > fallbackCap) {
          combinedSearchDuration = fallbackCap;
        }
      }

      var gaugeMaxDepth = effectiveEngineSettings.maxDepthFor(
        EngineComponent.evaluationGauge,
      );
      var pvMaxDepth = effectiveEngineSettings.maxDepthFor(
        EngineComponent.principalVariation,
      );
      var combinedMaxDepth =
          gaugeMaxDepth <= pvMaxDepth ? gaugeMaxDepth : pvMaxDepth;
      if (combinedMaxDepth < 1) {
        combinedMaxDepth = 1;
      } else if (combinedMaxDepth > 60) {
        combinedMaxDepth = 60;
      }

      // Generate cache key with multiPV count to avoid wrong PV count collisions
      final cacheKey = _fenCacheKey(fenToAnalyze, multiPV: configuredMultiPV);

      final depthTracker = ref.read(engineDepthTrackerProvider.notifier);

      // CHECKMATE DETECTION: If position is checkmate, set mate=0 and high eval immediately
      if (currentPosition!.isCheckmate) {
        _releaseLog('🎯 EVAL: Position is checkmate, setting mate=0');
        depthTracker.clear(
          EngineComponent.evaluationGauge,
          reason: 'checkmate',
        );
        depthTracker.clear(
          EngineComponent.principalVariation,
          reason: 'checkmate',
        );
        depthTracker.clear(EngineComponent.cascadeEval, reason: 'checkmate');
        final checkmateEval =
            currentPosition.turn == Side.white
                ? -100.0
                : 100.0; // Side that got mated loses
        state = AsyncValue.data(
          initialState.copyWith(
            evaluation: checkmateEval,
            mate: 0, // Checkmate delivered
            isEvaluating: false,
            principalVariations: const [], // No variations in checkmate
            principalVariationsBaseFen: null,
          ),
        );
        return;
      }

      // NOTE: cacheKey is now defined above (after getting configuredMultiPV)

      CloudEval? primaryEval;
      double? evaluation;
      List<AnalysisLine> pvLines = const [];

      // OPTIMIZATION: Skip recently failed evaluations (avoid hammering engine)
      final lastFailure = _failedEvalTimestamps[cacheKey];
      if (!force &&
          lastFailure != null &&
          DateTime.now().difference(lastFailure) < const Duration(seconds: 3)) {
        _releaseLog('⚠️ EVAL: Skipping (recent failure < 3s ago)');
        state = AsyncValue.data(
          initialState.copyWith(
            isEvaluating: false,
            evaluation: initialState.evaluation ?? 0.0,
            principalVariations: const [],
            principalVariationsBaseFen: null,
          ),
        );
        return;
      }

      // OPTIMIZATION: Coalesce duplicate requests for same position
      if (!force &&
          _activeEvalKey == cacheKey &&
          _activeEvalRequestId != null) {
        // Check if stale (> 15s for deep staged analysis)
        final isStale =
            _activeEvalStartTime != null &&
            DateTime.now().difference(_activeEvalStartTime!) >
                const Duration(seconds: 15);

        if (isStale) {
          _releaseLog(
            '⚠️ EVAL: Stale request (${DateTime.now().difference(_activeEvalStartTime!).inSeconds}s), forcing fresh eval',
          );
          state = AsyncValue.data(initialState.copyWith(isEvaluating: false));
          _activeEvalRequestId = null;
          _activeEvalKey = null;
          _activeEvalStartTime = null;
        } else {
          _releaseLog('⏭️ EVAL: Coalescing (already evaluating same position)');
          return; // Let existing request complete
        }
      }

      _registerPendingEvaluation(fen);

      if (!keepDepth) {
        depthTracker.clear(
          EngineComponent.evaluationGauge,
          reason: 'new evaluation request',
        );
        depthTracker.clear(
          EngineComponent.principalVariation,
          reason: 'new evaluation request',
        );
        depthTracker.clear(
          EngineComponent.cascadeEval,
          reason: 'new evaluation request',
        );
      }

      final currentRequestId = requestId = ++_evalRequestCounter;
      _activeEvalKey = cacheKey;
      _activeEvalRequestId = currentRequestId;
      _activeEvalStartTime = DateTime.now(); // Track when this request started

      final baselineState = state.value ?? initialState;
      if (keepPvs) {
        _releaseLog(
          '🎯 EVAL: Refreshing evaluation while preserving current PVs for ${fen.split(' ').take(3).join(' ')}',
        );
      } else {
        _releaseLog(
          '🎯 EVAL: Clearing stale PVs, starting fresh evaluation for FEN: ${fen.split(' ').take(3).join(' ')}...',
        );
      }
      if (keepPvs) {
        state = AsyncValue.data(baselineState.copyWith(isEvaluating: true));
      } else {
        state = AsyncValue.data(
          baselineState.copyWith(
            shapes: const ISet.empty(),
            isEvaluating: true,
            principalVariations: const [],
            principalVariationsBaseFen: null,
            analysisState: baselineState.analysisState.copyWith(
              suggestionLines: const [],
            ),
          ),
        );
      }

      _releaseLog(
        '🎯 EVAL START: Evaluating position $fen (requesting $configuredMultiPV PVs)',
      );

      // Fast-path local/Supabase cache lookup, but do not block Stockfish startup
      // for long network waits. This keeps the engine responsive on cache misses.
      try {
        _releaseLog(
          '🎯 EVAL: Requesting cascade evaluation (local → Supabase cache only) with $configuredMultiPV PVs...',
        );
        final cascadeEval = await ref
            .read(
              cascadeEvalProviderForBoard(
                CascadeEvalParams(
                  fen: fenToAnalyze,
                  multiPV: configuredMultiPV,
                  isCurrentPosition: true,
                ),
              ).future,
            )
            .timeout(
              _cascadeEvalSoftTimeout,
              onTimeout:
                  () => CloudEval(
                    fen: fenToAnalyze,
                    knodes: 0,
                    depth: 0,
                    pvs: const [],
                    requestedMultiPv: configuredMultiPV,
                  ),
            );
        if (cascadeEval.pvs.isNotEmpty) {
          primaryEval = cascadeEval;
          final rawCp = cascadeEval.pvs.first.cp;
          final rawEval = rawCp / 100.0;
          evaluation = _getConsistentEvaluation(rawEval, fenToAnalyze);
          final cascadeMate = _getConsistentMate(
            cascadeEval.pvs.first.mate,
            fenToAnalyze,
          );

          if (mounted) {
            final previewState = state.value;
            if (previewState != null) {
              state = AsyncValue.data(
                previewState.copyWith(
                  evaluation: evaluation,
                  mate: cascadeMate,
                  isEvaluating: true,
                ),
              );
            }
          }

          final cascadeFenParts = fenToAnalyze.split(' ');
          final cascadeSideToMove =
              cascadeFenParts.length >= 2 ? cascadeFenParts[1] : '-';
          _releaseLog(
            '🔍 EVAL PIPELINE: fen=$fenToAnalyze, side=$cascadeSideToMove, rawCp=$rawCp, rawEval=$rawEval, evaluation=$evaluation, whitePerspective=${cascadeEval.pvs.first.whitePerspective}',
          );
          _releaseLog(
            '🎯 EVAL: Building principal variations from cloud source...',
          );
          final cascadeLines = await _buildPrincipalVariations(
            fenToAnalyze,
            cascadeEval.pvs,
          );
          var mergedCascadeLines = _mergePvProgress(pvLines, cascadeLines);
          if (mergedCascadeLines.length > configuredMultiPV) {
            mergedCascadeLines = mergedCascadeLines
                .take(configuredMultiPV)
                .toList(growable: false);
          }
          pvLines = mergedCascadeLines;

          if (pvLines.isEmpty && cascadeEval.pvs.isNotEmpty) {
            _releaseLog(
              '🔄 RETRY: Cloud PV building failed, retrying immediately...',
            );

            if (!mounted) {
              _releaseLog('🚫 RETRY CANCELLED: Provider disposed');
              return;
            }

            final currentState = state.value;
            if (currentState != null) {
              final currentPos =
                  currentState.isAnalysisMode
                      ? currentState.analysisState.position
                      : currentState.position;
              if (currentPos != null) {
                final currentFenBase = currentPos.fen
                    .split(' ')
                    .take(3)
                    .join(' ');
                final targetFenBase = fen.split(' ').take(3).join(' ');

                if (currentFenBase != targetFenBase) {
                  _releaseLog(
                    '🚫 RETRY CANCELLED: Position changed during delay (was: $targetFenBase, now: $currentFenBase)',
                  );
                  if (currentState.isEvaluating) {
                    state = AsyncValue.data(
                      currentState.copyWith(isEvaluating: false),
                    );
                  }
                  return;
                }
              }
            }

            final retryLines = await _buildPrincipalVariations(
              fenToAnalyze,
              cascadeEval.pvs,
            );
            if (retryLines.isNotEmpty) {
              pvLines = _mergePvProgress(pvLines, retryLines);
              _releaseLog('✅ RETRY: Cloud PV building succeeded on retry');
            } else {
              _releaseLog(
                '❌ RETRY: Cloud PV building failed again, will try Stockfish',
              );
            }
          }

          _releaseLog(
            '🎯 EVAL: CASCADE SUCCESS - returned ${pvLines.length} variants from ${cascadeEval.pvs.length} cloud PVs, eval=$evaluation',
          );
          if (pvLines.isNotEmpty && mounted) {
            final snapshot = state.value;
            if (snapshot != null) {
              final inAnalysis = snapshot.isAnalysisMode;
              final positionCascade =
                  inAnalysis
                      ? snapshot.analysisState.position
                      : snapshot.position;
              final basePointerCascade =
                  inAnalysis ? snapshot.analysisState.movePointer : null;
              final mergedCascade = _mergePvProgress(
                snapshot.principalVariations,
                pvLines,
              );
              pvLines = mergedCascade;
              final updatedCascade = snapshot.copyWith(
                evaluation: evaluation,
                mate: _getConsistentMate(
                  cascadeEval.pvs.first.mate,
                  fenToAnalyze,
                ),
                isEvaluating: true,
                principalVariations: mergedCascade,
                principalVariationsBaseFen: fen,
                analysisState: snapshot.analysisState.copyWith(
                  suggestionLines: mergedCascade,
                ),
              );
              state = AsyncValue.data(updatedCascade);
              final cascadeComplete =
                  pvLines.length >= configuredMultiPV ? 'complete' : 'partial';
              _releaseLog(
                '🎯 CASCADE APPLY: Applied ${pvLines.length} PVs to state ($cascadeComplete)',
              );
              if (positionCascade != null) {
                _applyPrincipalVariationResults(
                  currentState: updatedCascade,
                  currentPosition: positionCascade,
                  baseFen: fen,
                  baseMovePointer: basePointerCascade,
                  pvLines: mergedCascade,
                );
              }
            }
          }
        } else {
          _releaseLog('🎯 EVAL: Cascade returned empty PVs');
        }
      } catch (e) {
        _releaseLog('🎯 EVAL ERROR: Cascade failed for $fen: $e');
      }

      final multiPV = configuredMultiPV;
      final isCurrentlyVisible = currentVisiblePage == index;
      EngineSearchProgress? pendingProgress;
      final stockfishFuture = StockfishSingleton().evaluatePosition(
        fenToAnalyze,
        depth: combinedMaxDepth,
        multiPV: multiPV,
        isCurrentPosition: isCurrentlyVisible,
        searchDuration: combinedSearchDuration,
        maxDepth: combinedMaxDepth,
        allowCache: false,
        ownerId: _stockfishOwnerId, // Tag job with this provider's owner ID
        onDepthUpdate: (depth, knodes) {
          if (!mounted ||
              _cancelEvaluation ||
              _activeEvalRequestId != currentRequestId ||
              _activeEvalKey != cacheKey) {
            return;
          }
          final progress = EngineSearchProgress(
            depth: depth,
            kiloNodes: knodes,
            fenFragment: fenToAnalyze,
          );
          pendingProgress = progress;
          depthTracker.update(
            component: EngineComponent.evaluationGauge,
            progress: progress,
            context: 'local stockfish D:$depth',
            allowDecrease: !preserveDepthProgress,
          );
        },
        onPvUpdate: (pvs, depth) {
          if (!mounted ||
              _cancelEvaluation ||
              _activeEvalRequestId != currentRequestId ||
              _activeEvalKey != cacheKey) {
            return;
          }
          // CRITICAL: Update evaluation synchronously so the eval bar
          // never stalls while depth keeps increasing. Previously, the
          // entire callback was wrapped in Future<void> which could
          // silently bail at guard conditions or throw, leaving the
          // eval bar stuck on "..." while onDepthUpdate (synchronous)
          // kept advancing the depth display.
          try {
            if (!mounted) return;
            final currentState = state.value;
            if (currentState == null) return;
            final pos =
                currentState.isAnalysisMode
                    ? currentState.analysisState.position
                    : currentState.position;
            if (pos == null) return;
            final currentFenBase = pos.fen.split(' ').take(3).join(' ');
            final targetFenBase = fen.split(' ').take(3).join(' ');
            if (currentFenBase != targetFenBase) return;

            final cp = pvs.first.cp;
            final newEval = _getConsistentEvaluation(cp / 100.0, fenToAnalyze);
            final mateScore = _getConsistentMate(pvs.first.mate, fenToAnalyze);
            evaluation = newEval;

            var workingState = currentState.copyWith(
              evaluation: newEval,
              mate: mateScore,
              isEvaluating: true,
            );
            state = AsyncValue.data(workingState);

            // Only rebuild expensive PV lines at milestone depths.
            // Intermediate depths only update the eval bar above.
            // The bestmove handler always builds final PVs regardless.
            final isPvMilestone = depth <= 1 || depth % 4 == 0;
            if (!isPvMilestone) return;

            // Build PV lines asynchronously — the heavy work is
            // deferred but eval bar is already updated above.
            Future<void>(() async {
              try {
                if (!mounted ||
                    _cancelEvaluation ||
                    _activeEvalRequestId != currentRequestId ||
                    _activeEvalKey != cacheKey) {
                  return;
                }
                final visiblePage = ref.read(currentlyVisiblePageIndexProvider);
                if (visiblePage != index) return;

                var lines = await _buildPrincipalVariations(fenToAnalyze, pvs);
                if (lines.isEmpty) return;
                if (lines.length > multiPV) {
                  lines = lines.take(multiPV).toList(growable: false);
                }

                if (!mounted ||
                    _cancelEvaluation ||
                    _activeEvalRequestId != currentRequestId ||
                    _activeEvalKey != cacheKey) {
                  return;
                }

                primaryEval = CloudEval(
                  fen: fenToAnalyze,
                  knodes: 0,
                  depth: depth,
                  pvs: pvs,
                  requestedMultiPv: multiPV,
                );

                // Re-read state to avoid overwriting concurrent updates
                final freshState = state.value ?? workingState;
                final mergedLines = _mergePvProgress(
                  freshState.principalVariations,
                  lines,
                );
                pvLines = mergedLines;

                final progress =
                    pendingProgress ??
                    EngineSearchProgress(
                      depth: depth,
                      kiloNodes: 0,
                      fenFragment: fenToAnalyze,
                    );
                if (pendingProgress == null) {
                  depthTracker.update(
                    component: EngineComponent.evaluationGauge,
                    progress: progress,
                    context: 'progressive D:$depth',
                    allowDecrease: !preserveDepthProgress,
                  );
                }
                depthTracker.update(
                  component: EngineComponent.principalVariation,
                  progress: progress,
                  context: 'progressive D:$depth',
                  allowDecrease: !preserveDepthProgress,
                );
                pendingProgress = null;

                final basePointer =
                    freshState.isAnalysisMode
                        ? freshState.analysisState.movePointer
                        : null;
                final hasPrimaryPv = mergedLines.isNotEmpty;
                final nextState = freshState.copyWith(
                  evaluation: newEval,
                  isEvaluating: !hasPrimaryPv,
                  mate: mateScore,
                  principalVariations: mergedLines,
                  principalVariationsBaseFen: fen,
                  analysisState: freshState.analysisState.copyWith(
                    suggestionLines: mergedLines,
                  ),
                );
                state = AsyncValue.data(nextState);
                _applyPrincipalVariationResults(
                  currentState: nextState,
                  currentPosition: pos,
                  baseFen: fen,
                  baseMovePointer: basePointer,
                  pvLines: mergedLines,
                );
              } catch (e) {
                _releaseLog('⚠️ PV BUILD: Error building PV lines: $e');
              }
            });
          } catch (e) {
            _releaseLog('⚠️ PV UPDATE: Error in synchronous eval update: $e');
          }
        },
      );

      var stockfishFailed = false;
      try {
        final stockfishResult = await stockfishFuture;

        if (stockfishResult.isCancelled) {
          _releaseLog(
            '🎯 EVAL: Stockfish result cancelled before completion for $fen',
          );
          if (mounted && _activeEvalRequestId == currentRequestId) {
            _activeEvalRequestId = null;
            _activeEvalKey = null;
            _activeEvalStartTime = null;
            // Only clear isEvaluating if THIS is still the active eval.
            // A newer eval may already be running with isEvaluating: true;
            // clearing it here would leave the UI stuck in "..." on Android.
            final snapshot = state.value;
            if (snapshot != null && snapshot.isEvaluating) {
              state = AsyncValue.data(snapshot.copyWith(isEvaluating: false));
            }
          }

          // Only retry if NOT caused by watchdog — watchdog has its own retry path.
          if (mounted &&
              !_cancelEvaluation &&
              _consecutiveWatchdogTimeouts == 0) {
            Future.microtask(() {
              if (!mounted ||
                  _cancelEvaluation ||
                  _consecutiveWatchdogTimeouts > 0) {
                return;
              }
              final latestState = state.value;
              if (latestState == null) return;
              final latestPosition =
                  latestState.isAnalysisMode
                      ? latestState.analysisState.position
                      : latestState.position;
              final latestFen = latestPosition?.fen;
              if (latestFen != null &&
                  _normalizeFen(latestFen) == _normalizeFen(fen)) {
                _releaseLog('🎯 EVAL: Retrying evaluation after cancellation');
                _evaluatePosition(force: true);
              }
            });
          }
          return;
        }

        if (!mounted || _cancelEvaluation) return;
        if (stockfishResult.pvs.isNotEmpty && mounted) {
          primaryEval = CloudEval(
            fen: fenToAnalyze,
            knodes: stockfishResult.knodes,
            depth: stockfishResult.depth,
            pvs: stockfishResult.pvs,
            requestedMultiPv: multiPV,
          );
          final finalProgress = EngineSearchProgress(
            depth: stockfishResult.depth,
            kiloNodes: stockfishResult.knodes,
            fenFragment: fenToAnalyze,
          );
          depthTracker.update(
            component: EngineComponent.evaluationGauge,
            progress: finalProgress,
            context: 'progressive final',
            allowDecrease: !preserveDepthProgress,
          );
          depthTracker.update(
            component: EngineComponent.principalVariation,
            progress: finalProgress,
            context: 'progressive final',
            allowDecrease: !preserveDepthProgress,
          );
          // Always build final PVs at full depth — onPvUpdate skips
          // non-milestone depths, so the latest PVs may be stale.
          {
            var finalLines = await _buildPrincipalVariations(
              fenToAnalyze,
              stockfishResult.pvs,
            );
            if (finalLines.isNotEmpty && mounted) {
              if (finalLines.length > configuredMultiPV) {
                finalLines = finalLines
                    .take(configuredMultiPV)
                    .toList(growable: false);
              }
              pvLines = _mergePvProgress(pvLines, finalLines);
              final currentState = state.value;
              if (currentState != null) {
                final basePointer =
                    currentState.isAnalysisMode
                        ? currentState.analysisState.movePointer
                        : null;
                final updatedState = currentState.copyWith(
                  evaluation: _getConsistentEvaluation(
                    stockfishResult.pvs.first.cp / 100.0,
                    fenToAnalyze,
                  ),
                  mate: _getConsistentMate(
                    stockfishResult.pvs.first.mate,
                    fenToAnalyze,
                  ),
                  isEvaluating: false,
                  principalVariations: pvLines,
                  principalVariationsBaseFen: fen,
                  analysisState: currentState.analysisState.copyWith(
                    suggestionLines: pvLines,
                  ),
                );
                state = AsyncValue.data(updatedState);
                final currentPositionFinal =
                    updatedState.isAnalysisMode
                        ? updatedState.analysisState.position
                        : updatedState.position!;
                _applyPrincipalVariationResults(
                  currentState: updatedState,
                  currentPosition: currentPositionFinal,
                  baseFen: fen,
                  baseMovePointer: basePointer,
                  pvLines: pvLines,
                );
              }
            }
          }
        }
      } catch (e, stack) {
        stockfishFailed = true;
        _releaseLog(
          '🎯 EVAL ERROR: Stockfish progressive run failed for $fen: $e',
        );
        _releaseLog('Stack: $stack');
      }

      if (stockfishFailed &&
          mounted &&
          !_cancelEvaluation &&
          _consecutiveWatchdogTimeouts == 0) {
        Future.microtask(() {
          if (!mounted ||
              _cancelEvaluation ||
              _consecutiveWatchdogTimeouts > 0) {
            return;
          }
          final latestState = state.value;
          if (latestState == null) return;
          final latestPosition =
              latestState.isAnalysisMode
                  ? latestState.analysisState.position
                  : latestState.position;
          final latestFen = latestPosition?.fen;
          if (latestFen != null &&
              _normalizeFen(latestFen) == _normalizeFen(fen)) {
            _releaseLog('🎯 EVAL: Retrying evaluation after Stockfish failure');
            _evaluatePosition(force: true);
          }
        });
      }

      if (evaluation == null && (primaryEval?.pvs.isNotEmpty ?? false)) {
        evaluation = _getConsistentEvaluation(
          primaryEval!.pvs.first.cp / 100.0,
          fenToAnalyze,
        );
      }

      // CRITICAL FIX: Show evaluation even if PVs fail to convert
      // During live games with rapid moves, PV conversion might fail due to race conditions,
      // but we still want to show the evaluation bar and prevent stuck loading state
      if (primaryEval == null) {
        _releaseLog('❌ EVAL FAILED: No primaryEval available for $fen');
        _failedEvalTimestamps[cacheKey] = DateTime.now();
        if (mounted) {
          final fallbackState = state.value;
          if (fallbackState != null) {
            state = AsyncValue.data(
              fallbackState.copyWith(
                isEvaluating: false,
                evaluation: fallbackState.evaluation ?? 0,
              ),
            );
          }
        }
        return;
      }

      evaluation ??= _getConsistentEvaluation(
        primaryEval!.pvs.first.cp / 100.0,
        fenToAnalyze,
      );

      // CRITICAL: Always show evaluation even if PVs fail
      // Show eval bar immediately, PV cards can come later via retry
      if (pvLines.isEmpty && (primaryEval?.pvs.isNotEmpty ?? false)) {
        _releaseLog(
          '⚠️ EVAL: Have evaluation ($evaluation) but PV conversion failed',
        );
        _releaseLog('   primaryEval.pvs.length=${primaryEval?.pvs.length}');
        _releaseLog(
          '   First PV: moves=${primaryEval?.pvs.first.moves}, cp=${primaryEval?.pvs.first.cp}',
        );

        // IMMEDIATE UPDATE: Show eval bar with loading PVs indicator
        if (!mounted) return;
        final currentSnapshot = state.value;
        if (currentSnapshot != null) {
          state = AsyncValue.data(
            currentSnapshot.copyWith(
              evaluation: evaluation,
              mate: _getConsistentMate(
                primaryEval!.pvs.first.mate,
                fenToAnalyze,
              ),
              isEvaluating: true, // Keep loading state until PVs arrive
              principalVariations: const [],
              principalVariationsBaseFen: null,
              analysisState: currentSnapshot.analysisState.copyWith(
                suggestionLines: const [],
              ),
            ),
          );
        }

        // Schedule ONE retry for PVs - don't loop indefinitely
        // Capture primaryEval in local scope for null safety
        final evalForRetry = primaryEval;
        Future.delayed(const Duration(milliseconds: 300), () async {
          if (!mounted || _cancelEvaluation) return;
          final currentState = state.value;
          if (currentState == null) return;

          // Check if we're still on the same position
          final currentPos =
              currentState.isAnalysisMode
                  ? currentState.analysisState.position
                  : currentState.position;
          if (currentPos == null) return;

          final currentFenBase = currentPos.fen.split(' ').take(3).join(' ');
          final targetFenBase = fen.split(' ').take(3).join(' ');

          // Only retry if still on same position and still no PVs
          if (evalForRetry == null) {
            return;
          }

          if (currentFenBase == targetFenBase &&
              currentState.principalVariations.isEmpty &&
              evalForRetry.pvs.isNotEmpty) {
            _releaseLog(
              '🔄 RETRY: Re-building PVs for position $targetFenBase',
            );
            final retryPvLines = await _buildPrincipalVariations(
              fenToAnalyze,
              evalForRetry.pvs,
            );

            if (retryPvLines.isNotEmpty && mounted) {
              final latestState = state.value;
              if (latestState != null) {
                final latestPos =
                    latestState.isAnalysisMode
                        ? latestState.analysisState.position
                        : latestState.position;
                final latestFenBase = latestPos?.fen
                    .split(' ')
                    .take(3)
                    .join(' ');

                // Only apply if position hasn't changed
                if (latestFenBase == targetFenBase) {
                  _releaseLog(
                    '✅ RETRY SUCCESS: Applying ${retryPvLines.length} PVs',
                  );
                  final basePointer =
                      latestState.isAnalysisMode
                          ? latestState.analysisState.movePointer
                          : null;
                  final hasCompletePv =
                      configuredMultiPV <= 0 ||
                      retryPvLines.length >= configuredMultiPV;

                  final mergedRetryLines = _mergePvProgress(
                    latestState.principalVariations,
                    retryPvLines,
                  );
                  state = AsyncValue.data(
                    latestState.copyWith(
                      principalVariations: mergedRetryLines,
                      principalVariationsBaseFen: fen,
                      isEvaluating:
                          hasCompletePv ? false : latestState.isEvaluating,
                      variantBaseFen: fen,
                      variantBaseMovePointer: basePointer,
                      analysisState: latestState.analysisState.copyWith(
                        suggestionLines: mergedRetryLines,
                      ),
                    ),
                  );

                  _applyPrincipalVariationResults(
                    currentState: state.value!,
                    currentPosition: latestPos!,
                    baseFen: fen,
                    baseMovePointer: basePointer,
                    pvLines: mergedRetryLines,
                  );
                } else {
                  _releaseLog(
                    '🚫 RETRY CANCELLED: Position changed during retry',
                  );
                }
              }
            } else {
              _releaseLog('❌ RETRY FAILED: Still no PVs after retry');
            }
          }
        });
        // Continue with rest of the method to cache what we have
      } else if (pvLines.isEmpty) {
        _releaseLog('⚠️ EVAL: No PVs available from any source');
      }

      // OPTIMIZATION: Don't await cache persistence - run in background for speed
      // User sees evaluation immediately while caching happens asynchronously
      if (primaryEval != null && _shouldPersistCloudEval(primaryEval!)) {
        final cache = ref.read(localEvalCacheProvider);
        final persist = ref.read(persistCloudEvalProvider);
        Future.wait([
          persist.call(fenToAnalyze, primaryEval!),
          cache.save(
            fenToAnalyze,
            primaryEval!,
            multiPV: primaryEval!.requestedMultiPv ?? primaryEval!.pvs.length,
          ),
        ]).catchError((e) {
          _releaseLog('Background persist failed for $fenToAnalyze: $e');
          return <void>[];
        });
      } else if (primaryEval != null) {
        final pvMovesCount =
            primaryEval!.pvs.isNotEmpty
                ? primaryEval!.pvs.first.fullMoveCount
                : 0;
        _releaseLog(
          '⚠️ PERSIST SKIPPED: Eval depth=${primaryEval!.depth}, fullMoves=$pvMovesCount',
        );
      }

      if (!mounted || _cancelEvaluation) return;
      if (state.value == null) {
        return;
      }
      if (_activeEvalRequestId != currentRequestId) {
        // Don't clear isEvaluating - another request is handling it
        return;
      }

      // Normalize PV list size to match configured MultiPV whenever possible
      if (pvLines.length > configuredMultiPV) {
        _releaseLog(
          '🎯 EVAL: Trimming PV list from ${pvLines.length} to $configuredMultiPV as per settings',
        );
        pvLines = pvLines.take(configuredMultiPV).toList(growable: false);
      } else if (pvLines.length < configuredMultiPV) {
        _releaseLog(
          '🎯 EVAL: Only ${pvLines.length} PV lines available (requested $configuredMultiPV)',
        );
      }

      var currentSnapshot = state.value;
      if (currentSnapshot == null) {
        // CRITICAL FIX: Clear evaluating state on early return
        if (initialState.isEvaluating) {
          state = AsyncValue.data(initialState.copyWith(isEvaluating: false));
        }
        return;
      }

      final inAnalysis = currentSnapshot.isAnalysisMode;
      final position =
          inAnalysis
              ? currentSnapshot.analysisState.position
              : currentSnapshot.position!;

      // Allow small FEN differences (like move counters) during variant exploration
      final currentFenBase = position.fen.split(' ').take(3).join(' ');
      final evalFenBase = fen.split(' ').take(3).join(' ');

      if (currentFenBase != evalFenBase) {
        _releaseLog(
          '🎯 EVAL: Position changed during eval (current=$currentFenBase vs eval=$evalFenBase)',
        );
        state = AsyncValue.data(currentSnapshot.copyWith(isEvaluating: false));
        return;
      }

      final basePointer =
          inAnalysis ? currentSnapshot.analysisState.movePointer : null;
      final primaryPvs = primaryEval?.pvs;
      final bool hasPrimaryPv = primaryPvs != null && primaryPvs.isNotEmpty;
      final int? rawMateScore =
          hasPrimaryPv
              ? primaryPvs.first.mate
              : null; // Use engine mate directly, null if no mate

      // BUG FIX: Validate mate=0 - only allow it if position is actually checkmate
      // This fixes the bug where "M" appears on regular positions
      final int? mateScore =
          (rawMateScore == 0 && !position.isCheckmate)
              ? null // Invalid mate=0, treat as regular position
              : rawMateScore;

      if (rawMateScore == 0 && !position.isCheckmate) {
        _releaseLog(
          '⚠️ EVAL: API returned mate=0 for non-checkmate position, ignoring mate value',
        );
      }

      _failedEvalTimestamps.remove(cacheKey);

      // CRITICAL: Don't overwrite variant base if we're exploring a variant
      final inVariantExploration =
          currentSnapshot.selectedVariantIndex != null &&
          currentSnapshot.variantMovePointer.isNotEmpty &&
          currentSnapshot.variantBaseFen != null;

      final Position positionForArrows =
          currentSnapshot.isThreatsMode ? positionForAnalysis : position;

      // CRITICAL: Use multi-variant arrows if variant selected, otherwise use best move
      final ISet<Shape> shapes;
      if (currentSnapshot.selectedVariantIndex != null && pvLines.isNotEmpty) {
        shapes = _getAllVariantArrowShapes(
          pvLines,
          currentSnapshot.selectedVariantIndex!,
          isThreatsMode: currentSnapshot.isThreatsMode,
        );
      } else {
        // Fallback: if primaryEval is null, build a minimal CloudEval from pvLines
        final evalForShapes =
            primaryEval ??
            CloudEval(
              fen: positionForArrows.fen,
              knodes: 0,
              depth: 0,
              pvs:
                  pvLines
                      .map(
                        (line) => Pv(
                          moves: line.moves.map((m) => m.uci).join(' '),
                          cp: ((line.evaluation ?? 0) * 100).toInt(),
                          isMate: line.isMate,
                          mate: line.mate,
                          whitePerspective: true,
                        ),
                      )
                      .toList(),
              requestedMultiPv: pvLines.length,
            );
        shapes = getBestMoveShape(positionForArrows, evalForShapes);
      }

      final overlayShapes =
          currentSnapshot.isPvPreviewActive
              ? const ISet<Shape>.empty()
              : shapes;

      if (effectiveSkipPv) {
        currentSnapshot = currentSnapshot.copyWith(
          evaluation: evaluation,
          mate: mateScore,
          isEvaluating: false,
          shapes: overlayShapes,
        );
        state = AsyncValue.data(currentSnapshot);
      } else {
        currentSnapshot = currentSnapshot.copyWith(
          evaluation: evaluation,
          mate: mateScore,
          isEvaluating: false,
          shapes: overlayShapes,
          principalVariations: pvLines,
          principalVariationsBaseFen: fen,
          // Only update variantBaseFen if NOT in variant exploration
          variantBaseFen:
              inVariantExploration ? currentSnapshot.variantBaseFen : fen,
          variantBaseMovePointer:
              inVariantExploration
                  ? currentSnapshot.variantBaseMovePointer
                  : basePointer,
          analysisState: currentSnapshot.analysisState.copyWith(
            suggestionLines: pvLines,
          ),
        );
        state = AsyncValue.data(currentSnapshot);

        // CRITICAL: Apply PV results to handle variant extension and auto-resume
        _applyPrincipalVariationResults(
          currentState: currentSnapshot,
          currentPosition: position,
          baseFen: fen,
          baseMovePointer: basePointer,
          pvLines: pvLines,
        );
      }

      // Note: Removed supplemental eval since Stockfish is now primary with MultiPV=3
    } catch (e) {
      if (!_cancelEvaluation) {
        _releaseLog('Evaluation error: $e');
      }
      if (mounted) {
        final fallbackState = state.value;
        if (fallbackState != null) {
          state = AsyncValue.data(fallbackState.copyWith(isEvaluating: false));
        }
      }
    } finally {
      if (requestId != null && _activeEvalRequestId == requestId) {
        _activeEvalRequestId = null;
        _activeEvalKey = null;
        _activeEvalStartTime = null; // Clear start time on completion
      }
      if (lastEvaluatedFen != null) {
        _resolvePendingEvaluation(lastEvaluatedFen);
      }
    }
  }

  void _syncAnalysisFromNavigator(ChessGameNavigatorState navigatorState) {
    final current = state.value;
    if (current == null) {
      return;
    }

    // CRITICAL FIX: Prevent duplicate sync when board is already at target position.
    // Both the navigator listener and manual sync call this method, which caused
    // race conditions during rapid tapping that could skip moves.
    // We must check BOTH movePointer AND FEN to ensure we don't skip a sync when
    // the pointer matches but the position is actually different (race condition).
    // IMPORTANT: Never skip if game is null - first initialization must set the game.
    final currentPointer = current.analysisState.movePointer;
    final targetPointer = navigatorState.movePointer;
    final currentFen = current.analysisState.position.fen;
    final targetFen = navigatorState.currentFen;
    final gameAlreadySet = current.analysisState.game != null;
    if (gameAlreadySet &&
        listEquals(currentPointer, targetPointer) &&
        currentFen == targetFen) {
      // Already at target position with matching FEN and game is set, skip redundant sync
      return;
    }

    _releaseLog(
      '🎯 SYNC FROM NAVIGATOR: Syncing to pointer=${navigatorState.movePointer}',
    );
    if (navigatorState.currentMove != null) {
      _releaseLog(
        '🎯 SYNC FROM NAVIGATOR: Current move is ${navigatorState.currentMove!.san} (move #${navigatorState.currentMove!.num})',
      );
    }

    try {
      final position = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(navigatorState.currentFen),
      );
      final sameFenAsCurrent =
          _normalizeFen(current.analysisState.position.fen) ==
          _normalizeFen(position.fen);

      Move? lastMove;
      final currentMove = navigatorState.currentMove;
      if (currentMove != null) {
        final parsed = Move.parse(currentMove.uci);
        if (parsed != null) {
          lastMove = parsed;
        }
      }

      // CRITICAL: Sync allMoves from navigator to ensure move history is displayed
      final movesFromNavigator =
          navigatorState.currentLine
              ?.map((chessMove) {
                final parsed = Move.parse(chessMove.uci);
                return parsed;
              })
              .whereType<Move>()
              .toList() ??
          const <Move>[];

      int currentMoveIndex;
      final chessMove = navigatorState.currentMove;
      if (chessMove == null) {
        currentMoveIndex = -1;
      } else {
        var moveNumber = chessMove.num;
        final whiteJustMoved = chessMove.turn == ChessColor.black;
        if (!whiteJustMoved) {
          moveNumber = (moveNumber - 1).clamp(1, moveNumber);
        }
        currentMoveIndex =
            whiteJustMoved ? (moveNumber - 1) * 2 : (moveNumber - 1) * 2 + 1;
      }

      final nextState = current.copyWith(
        analysisState: current.analysisState.copyWith(
          game: navigatorState.game,
          position: position,
          validMoves: makeLegalMoves(position),
          lastMove: lastMove,
          moveSans:
              navigatorState.currentLine?.map((move) => move.san).toList() ??
              const [],
          allMoves: movesFromNavigator, // Sync allMoves from navigator
          movePointer: navigatorState.movePointer,
          currentMoveIndex: currentMoveIndex,
          suggestionLines:
              sameFenAsCurrent
                  ? current.analysisState.suggestionLines
                  : const [], // Keep lines when navigator syncs same position.
        ),
        evaluation: sameFenAsCurrent ? current.evaluation : null,
        isEvaluating: sameFenAsCurrent ? current.isEvaluating : true,
      );

      var progressedState = _setVariantProgress(
        currentState: nextState,
        currentPosition: position,
      );

      state = AsyncValue.data(progressedState);

      // Reset cancellation guard whenever the navigation tracker changes so the next
      // scheduled evaluation is allowed to run if a transient cancel flag was set.
      _cancelEvaluation = false;
      _updateEvaluation();

      // Schedule auto-save when the game tree has changed (new moves/variations)
      if (navigatorState.game != current.analysisState.game) {
        _scheduleAutoSave();
      }
    } catch (e) {
      _releaseLog('Failed to sync analysis navigator state: $e');
    }
  }

  ISet<Shape> getBestMoveShape(Position pos, CloudEval? cloudEval) {
    ISet<Shape> shapes = const ISet.empty();
    if (cloudEval?.pvs.isNotEmpty ?? false) {
      final arrowShapes = <Arrow>[];

      // CRITICAL: Validate that the PVs are for the correct position
      // The cloudEval.fen should match the position we're displaying arrows for
      if (cloudEval!.fen != pos.fen) {
        _releaseLog('⚠️ PV ARROWS: Skipping - PVs are for different position');
        _releaseLog('   Current FEN: ${pos.fen}');
        _releaseLog('   Eval FEN: ${cloudEval.fen}');
        return const ISet.empty();
      }

      // Use maxArrowsOnBoard setting to limit number of arrows (independent of PV lines)
      final engineSettings = ref.read(engineSettingsProviderNew).valueOrNull;
      final maxArrows = engineSettings?.getMaxArrowsOnBoard() ?? 3;
      final pvsToShow = cloudEval.pvs.take(maxArrows).toList();

      for (int i = 0; i < pvsToShow.length; i++) {
        final pv = pvsToShow[i];
        String bestMove =
            pv.moves.split(" ")[0].toLowerCase(); // Normalize to lowercase

        if (bestMove.length < 4 || bestMove.length > 5) {
          _releaseLog('Invalid best move UCI: $bestMove');
          continue; // Skip invalid UCI
        }

        try {
          // Use different colors/opacity for primary, secondary, tertiary moves
          final isThreatsMode = state.value?.isThreatsMode ?? false;
          final arrowColor =
              isThreatsMode
                  ? const Color(
                    0xFFFF0000,
                  ).withValues(alpha: i == 0 ? 1.0 : 0.7)
                  : switch (i) {
                    0 => const Color.fromARGB(255, 152, 179, 154),
                    1 => const Color.fromARGB(200, 152, 179, 154),
                    _ => const Color.fromARGB(150, 152, 179, 154),
                  };

          if (bestMove.contains('@')) {
            // Drop move (e.g., "p@e4")
            if (bestMove.length != 4 || bestMove[1] != '@') continue;
            String toStr = bestMove.substring(2, 4);
            Square to = Square.fromName(toStr);
            arrowShapes.add(
              Arrow(
                color: arrowColor,
                orig: to, // Same square as destination
                dest: to,
              ),
            );
          } else {
            // Normal move or promotion (e.g., "e2e4" or "e7e8q")
            String fromStr = bestMove.substring(0, 2);
            String toStr = bestMove.substring(2, 4);
            Square from = Square.fromName(fromStr);
            Square to = Square.fromName(toStr);

            // VALIDATION: Verify this move is legal for the current position
            // This ensures we're showing moves for the correct color
            final promotion = bestMove.length == 5 ? bestMove[4] : null;
            NormalMove? move;

            if (promotion != null) {
              // Promotion move
              final promRole = switch (promotion) {
                'q' => Role.queen,
                'r' => Role.rook,
                'b' => Role.bishop,
                'n' => Role.knight,
                _ => Role.queen,
              };
              move = NormalMove(from: from, to: to, promotion: promRole);
            } else {
              move = NormalMove(from: from, to: to);
            }

            // Validate the move by trying to play it on the position
            bool isLegal = false;
            try {
              // If play succeeds, the move is legal
              pos.play(move);
              isLegal = true;
            } catch (e) {
              // If play throws an exception, the move is illegal
              isLegal = false;
            }

            if (!isLegal) {
              _releaseLog(
                '⚠️ PV ARROWS: Move $bestMove is not legal for position (turn: ${pos.turn})',
              );
              continue; // Skip illegal moves
            }

            arrowShapes.add(Arrow(color: arrowColor, orig: from, dest: to));
          }
        } catch (e) {
          // Parsing failed for this PV, continue with next
          _releaseLog('Error parsing PV $i best move UCI: $e');
          continue;
        }
      }

      if (arrowShapes.isNotEmpty) {
        shapes = arrowShapes.toISet();
      }
    } else {
      _releaseLog('No evaluation data available.');
    }
    return shapes;
  }

  ISet<Shape> _variantArrowShapes(
    AnalysisLine variant,
    int nextMoveIndex, {
    bool isThreatsMode = false,
  }) {
    if (nextMoveIndex < 0 || nextMoveIndex >= variant.moves.length) {
      return const ISet.empty();
    }
    final move = variant.moves[nextMoveIndex];
    if (move is! NormalMove) {
      return const ISet.empty();
    }
    try {
      final arrow = Arrow(
        color:
            isThreatsMode
                ? const Color(0xFFFF0000).withValues(alpha: 0.8)
                : kPrimaryColor.withValues(alpha: 0.8),
        orig: move.from,
        dest: move.to,
      );
      return [arrow].toISet();
    } catch (_) {
      return const ISet.empty();
    }
  }

  /// Show all 5 variant first moves as arrows with different opacity
  /// Stable variant colors - always in this order regardless of evaluations
  static const List<Color> _variantColors = [
    Color.fromARGB(180, 152, 179, 154), // Green - Always 1st variant
    Color.fromARGB(180, 100, 149, 237), // Blue - Always 2nd variant
    Color.fromARGB(180, 255, 165, 0), // Orange - Always 3rd variant
    Color.fromARGB(180, 255, 105, 180), // Pink - Always 4th variant
    Color.fromARGB(180, 147, 112, 219), // Purple - Always 5th variant
  ];

  /// Get color for a variant index (used for both arrows and card borders)
  /// Always returns the static variant color (Green/Blue/Orange/Pink/Purple)
  /// Selection is indicated by higher opacity, not different color
  Color getVariantColor(int variantIndex, bool isSelected) {
    if (variantIndex >= 0 && variantIndex < _variantColors.length) {
      // Use static variant color, adjust opacity for selection
      return _variantColors[variantIndex].withValues(
        alpha: isSelected ? 0.95 : 0.7,
      );
    }
    // Cycle through colors for any index beyond 5
    final colorIndex = variantIndex % _variantColors.length;
    return _variantColors[colorIndex].withValues(
      alpha: isSelected ? 0.95 : 0.7,
    );
  }

  ISet<Shape> _getAllVariantArrowShapes(
    List<AnalysisLine> variants,
    int selectedIndex, {
    bool isThreatsMode = false,
  }) {
    final arrows = <Arrow>[];

    // Use maxArrowsOnBoard setting to limit number of arrows
    final engineSettings = ref.read(engineSettingsProviderNew).valueOrNull;
    final maxArrows = engineSettings?.getMaxArrowsOnBoard() ?? 3;

    for (int i = 0; i < variants.length && i < maxArrows; i++) {
      final variant = variants[i];
      if (variant.moves.isEmpty) continue;

      final move = variant.moves[0];
      if (move is! NormalMove) continue;

      try {
        final arrowColor =
            isThreatsMode
                ? const Color(0xFFFF0000).withValues(alpha: i == 0 ? 0.95 : 0.7)
                : getVariantColor(i, i == selectedIndex);

        arrows.add(Arrow(color: arrowColor, orig: move.from, dest: move.to));
      } catch (_) {
        continue;
      }
    }

    return arrows.toISet();
  }

  ISet<Shape> _maybeSuppressShapes(
    ChessBoardStateNew state,
    ISet<Shape> candidate,
  ) {
    if (state.isPvPreviewActive) {
      return const ISet.empty();
    }
    return candidate;
  }

  String _normalizeFen(String fen) => fen.split(' ').take(4).join(' ');

  /// Parse the live game FEN into a display-only placeholder position.
  /// Returns null for non-live games, missing FEN, or parse failures.
  Position? _tryParseLiveFenPlaceholder() {
    if (!game.gameStatus.isOngoing) return null;
    final fen = game.fen;
    if (fen == null || fen.trim().isEmpty) return null;
    try {
      final setup = Setup.parseFen(fen.trim());
      return Chess.fromSetup(setup);
    } catch (_) {
      return null;
    }
  }

  /// Generate a "threat FEN" by flipping the side to move
  /// This allows analyzing what the opponent threatens on the current position
  String _getThreatFen(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 4) return fen;

    final turn = parts[1];
    final newTurn = turn == 'w' ? 'b' : 'w';
    parts[1] = newTurn;
    parts[3] = '-'; // Clear en passant target square
    return parts.join(' ');
  }

  /// Toggle threats mode on/off
  void toggleThreatsMode() {
    final currentState = state.value;
    if (currentState == null) return;

    final newMode = !currentState.isThreatsMode;
    state = AsyncValue.data(currentState.copyWith(isThreatsMode: newMode));

    // Force re-evaluation to show threats or return to normal
    _evaluatePosition(force: true);
  }

  void _updateEvaluation({
    bool force = false,
    bool preserveCurrentPvs = false,
    bool preserveDepthProgress = false,
  }) {
    if (_isLongPressing) return;

    if (force) {
      // Force requests should interrupt any pending scheduled evaluations
      EasyDebounce.cancel('evaluation-$index');
    }

    _cancelEvaluation = false;
    if (force) {
      _clearActiveEvalState();
    }

    final currentState = state.value;
    if (currentState == null) return;

    final currentPosition =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position;
    final currentFen = currentPosition?.fen;
    if (currentFen == null || currentFen.trim().isEmpty) return;

    // If an eval for the same position is already active, do not schedule a
    // new one. This avoids depth resets/flicker when unrelated UI updates
    // trigger _updateEvaluation repeatedly while browsing opening explorer.
    final fenToAnalyze =
        currentState.isThreatsMode ? _getThreatFen(currentFen) : currentFen;
    final activeCacheKey = _fenCacheKey(
      fenToAnalyze,
      multiPV: _currentMultiPvSetting(),
    );
    if (!force &&
        _activeEvalRequestId != null &&
        _activeEvalKey == activeCacheKey) {
      return;
    }

    final previewActive = currentState.isPvPreviewActive;
    final effectivePreservePvs = previewActive ? true : preserveCurrentPvs;
    final effectivePreserveDepth = previewActive ? true : preserveDepthProgress;
    final skipPvUpdates = previewActive;

    // CRITICAL: Clear stale PVs immediately when position changes
    if (currentState.principalVariations.isNotEmpty) {
      final fenToEval =
          currentState.isAnalysisMode
              ? currentState.analysisState.position.fen
              : currentState.position?.fen;

      // Check if current PVs match the position we're about to evaluate
      // Use stored PV base FEN to detect staleness
      final pvBaseFen =
          currentState.principalVariationsBaseFen ??
          currentState.variantBaseFen;
      if (pvBaseFen != null && fenToEval != null) {
        final pvFenBase = pvBaseFen.split(' ').take(3).join(' ');
        final currentFenBase = fenToEval.split(' ').take(3).join(' ');

        if (pvFenBase != currentFenBase) {
          _releaseLog('🎯 UPDATE EVAL: Clearing stale PVs for new position');
          state = AsyncValue.data(
            currentState.copyWith(
              principalVariations: const [],
              principalVariationsBaseFen: null,
              selectedVariantIndex: null,
              variantBaseFen: null,
              variantMovePointer: const [],
            ),
          );
        }
      }
    }

    void scheduleEvaluation() {
      if (_cancelEvaluation || !mounted) return;
      if (state.value == null) return;

      _releaseLog(
        force
            ? '🎯 EVAL: Forcing evaluation for current position'
            : '🎯 EVAL: Scheduling evaluation for current position',
      );
      final visibleIndex = ref.read(currentlyVisiblePageIndexProvider);
      final shouldForce = force || (visibleIndex == index);
      _evaluatePosition(
        force: shouldForce,
        preserveCurrentPvs: effectivePreservePvs,
        preserveDepthProgress: effectivePreserveDepth,
        skipPvUpdates: skipPvUpdates,
      );
    }

    if (force) {
      scheduleEvaluation();
    } else {
      // Debounce rapid navigation so we only evaluate after the user settles on a move
      EasyDebounce.debounce(
        'evaluation-$index',
        const Duration(milliseconds: 120),
        scheduleEvaluation,
      );
    }
  }

  void startLongPressForward() {
    _isLongPressing = true;
    _longPressTimer?.cancel();

    // Trigger initial haptic feedback
    HapticFeedback.mediumImpact();

    // Faster interval for smoother fast-forward (150ms instead of 300ms)
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      try {
        final currentState = state.value;
        final canAdvance =
            currentState?.isAnalysisMode == true
                ? _canAnalysisNavigatorMoveForward()
                : currentState?.canMoveForward == true;
        if (canAdvance && !_isProcessingMove) {
          // Light haptic feedback on each step
          HapticFeedback.selectionClick();
          unawaited(moveForward());
        } else {
          // Final haptic feedback when reaching end
          HapticFeedback.lightImpact();
          stopLongPress();
        }
      } on StateError {
        stopLongPress();
      }
    });
  }

  void startLongPressBackward() {
    _isLongPressing = true;
    _longPressTimer?.cancel();

    // Trigger initial haptic feedback
    HapticFeedback.mediumImpact();

    // Faster interval for smoother fast-backward (150ms instead of 300ms)
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      try {
        final currentState = state.value;
        final canRetreat =
            currentState?.isAnalysisMode == true
                ? _canAnalysisNavigatorMoveBackward()
                : currentState?.canMoveBackward == true;
        if (canRetreat && !_isProcessingMove) {
          // Light haptic feedback on each step
          HapticFeedback.selectionClick();
          unawaited(moveBackward());
        } else {
          // Final haptic feedback when reaching start
          HapticFeedback.lightImpact();
          stopLongPress();
        }
      } on StateError {
        stopLongPress();
      }
    });
  }

  double getWhiteRatio(double eval) {
    return (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
  }

  double getBlackRatio(double eval) => 1.0 - getWhiteRatio(eval);

  void stopLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _cancelEvaluation = true;
    if (_isLongPressing) {
      _isLongPressing = false;
      _cancelEvaluation = false;
      _updateEvaluation();
    }
  }

  @override
  void dispose() {
    stopLongPress();
    for (final request in _navigationQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete();
      }
    }
    _navigationQueue.clear();
    // Cancel debounce timer and fire a final auto-save
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer!.cancel();
      unawaited(_performAutoSave());
    }
    _autoSaveTimer = null;
    unawaited(_persistAnalysisState());
    _navigatorSubscription?.close();
    _navigatorSubscription = null;
    _cancelEvalWatchdog(resetPending: true);
    // Cancel this provider's Stockfish jobs on dispose to prevent orphaned jobs
    unawaited(
      StockfishSingleton().cancelEvaluationsForOwner(_stockfishOwnerId),
    );
    super.dispose();
  }
}

// Provider parameter to pass game directly instead of fetching from global provider
class ChessBoardProviderParams {
  final GamesTourModel game;
  final int index;

  /// Optional saved analysis for restoring full state (variations, comments, position)
  final SavedAnalysisData? savedAnalysisData;

  /// When true, the board starts at the last move instead of the starting position.
  /// Used by the opening explorer's "Analyze" action.
  final bool startAtLastMove;

  const ChessBoardProviderParams({
    required this.game,
    required this.index,
    this.savedAnalysisData,
    this.startAtLastMove = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessBoardProviderParams &&
          runtimeType == other.runtimeType &&
          game.gameId == other.game.gameId &&
          index == other.index;

  // Note: savedAnalysisData is intentionally excluded from equality/hashCode
  // It's initialization data, not provider identity. The provider is uniquely
  // identified by (gameId, index). For saved analyses, use a unique gameId.

  @override
  int get hashCode => game.gameId.hashCode ^ index.hashCode;
}

/// Data needed to restore a saved analysis state
class SavedAnalysisData {
  /// Unique ID of the saved analysis (for tracking).
  /// Null when opening a shared/read-only game (no save-back).
  final String? analysisId;

  /// Pre-built ChessGame with all variations
  final ChessGame chessGame;

  /// Comments keyed by variation pointer ID
  final Map<String, String> variationComments;

  /// Saved move pointer to restore navigation position
  final List<int>? movePointer;

  /// Board orientation preference
  final bool isBoardFlipped;

  /// Last viewed position (move index)
  final int lastViewedPosition;

  /// Title of the saved analysis (for auto-save updates)
  final String? title;

  /// Folder ID the analysis belongs to (for auto-save updates)
  final String? folderId;

  const SavedAnalysisData({
    this.analysisId,
    required this.chessGame,
    required this.variationComments,
    this.movePointer,
    required this.isBoardFlipped,
    required this.lastViewedPosition,
    this.title,
    this.folderId,
  });
}

final chessBoardScreenProviderNew = AutoDisposeStateNotifierProvider.family<
  ChessBoardScreenNotifierNew,
  AsyncValue<ChessBoardStateNew>,
  ChessBoardProviderParams
>((ref, params) {
  // DON'T watch global tournament provider - only watch THIS game's updates
  // This prevents rebuilds when other games in the tournament update
  return ChessBoardScreenNotifierNew(
    ref,
    game: params.game,
    index: params.index,
    savedAnalysisData: params.savedAnalysisData,
    startAtLastMove: params.startAtLastMove,
  );
});

List<Map<String, dynamic>> _analysisLinesWorker(Map<String, dynamic> payload) {
  try {
    final fen = payload['fen'] as String? ?? '';
    if (fen.isEmpty) return const [];

    final pvsData =
        (payload['pvs'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();

    final basePosition = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(fen),
    );

    // PV DISPLAY POLICY: Simple and flexible
    // - Display whatever PV moves are available from the source
    // - No caps, no minimums, no restrictions

    final results = <Map<String, dynamic>>[];

    for (final pvData in pvsData) {
      final movesString = pvData['moves'] as String? ?? '';
      if (movesString.isEmpty) continue;

      final tokens =
          movesString.split(' ').where((token) => token.isNotEmpty).toList();

      var position = basePosition;
      final uciMoves = <String>[];
      final sanMoves = <String>[];
      var valid = true;

      for (final token in tokens) {
        final parsedMove = Move.parse(token);
        if (parsedMove == null) {
          _releaseLog(
            '⚠️ UCI->SAN failed: "$token" could not be parsed as a valid move',
          );
          valid = false;
          break;
        }
        try {
          final (nextPosition, san) = position.makeSan(parsedMove);
          position = nextPosition;
          uciMoves.add(token);
          sanMoves.add(san);
        } catch (e) {
          Square? origin;
          if (parsedMove is NormalMove) {
            origin = parsedMove.from;
          }
          final piece = origin != null ? position.board.pieceAt(origin) : null;
          _releaseLog('⚠️ UCI->SAN failed: "$token" on ${position.fen} -> $e');
          if (origin != null) {
            _releaseLog(
              '   Piece at ${origin.name}: ${piece?.role.name ?? 'none'} ${piece?.color.name ?? ''}',
            );
          }
          valid = false;
          break;
        }
      }

      if (!valid || uciMoves.isEmpty) {
        continue;
      }

      final bool isMate = pvData['isMate'] == true;
      final int? rawMate =
          pvData['mate'] == null
              ? null
              : int.tryParse(pvData['mate'].toString());
      final int cpValue =
          pvData['cp'] is int
              ? pvData['cp'] as int
              : int.tryParse(pvData['cp']?.toString() ?? '0') ?? 0;

      results.add({
        'uci': uciMoves,
        'san': sanMoves,
        'isMate': isMate,
        'mate': rawMate,
        'cp': cpValue,
      });
    }

    return results;
  } catch (_) {
    return const [];
  }
}

const int kVariationCommentMaxChars = 280;
