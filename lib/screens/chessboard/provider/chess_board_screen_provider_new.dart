import 'dart:async';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator_state_manager.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:worker_manager/worker_manager.dart';

const int _kMaxPrincipalVariations = 3;

enum ChessboardView { favScorecard, tour, countryman }

final chessboardViewFromProviderNew = StateProvider<ChessboardView>((ref) {
  return ChessboardView.tour;
});

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

class ChessBoardScreenNotifierNew
    extends StateNotifier<AsyncValue<ChessBoardStateNew>> {
  ChessBoardScreenNotifierNew(
    this.ref, {
    required this.game,
    required this.index,
  }) : super(const AsyncValue.loading()) {
    _initializeState();
    _setupPgnStreamListener();
  }

  final Ref ref;
  GamesTourModel game;
  final int index;
  Timer? _longPressTimer;
  bool _hasParsedMoves = false;
  bool _isProcessingMove = false;
  bool _isLongPressing = false;
  bool _cancelEvaluation = false;
  bool _resumeVariantAutoPlay = false;
  bool _isPlayingVariant = false;
  final Map<String, double> _evaluationCache = {};
  final Map<String, int?> _mateCache = {};
  final Map<String, List<AnalysisLine>> _pvCache = {};
  int _evalRequestCounter = 0;
  int? _activeEvalRequestId;
  String? _activeEvalKey;
  ChessGame? _analysisGame;
  ChessGameNavigatorStateManager? _analysisStateManager;
  ProviderSubscription<ChessGameNavigatorState>? _navigatorSubscription;

  void _initializeState() {
    // Start with loading state so UI shows loading screen until parseMoves() completes
    // This prevents the board from briefly showing the starting position
    state = const AsyncValue.loading();
    parseMoves();
  }

  /// Get evaluation with consistent perspective for evaluation bar display
  /// BULLETPROOF evaluation perspective handler
  /// This method GUARANTEES that ALL evaluations are in WHITE'S PERSPECTIVE
  double _getConsistentEvaluation(double evaluation, String fen) {
    debugPrint(
      "🔍 EVAL WHITE PERSPECTIVE: FEN=$fen, eval=$evaluation (positive=WHITE advantage, negative=BLACK advantage)",
    );
    return evaluation;
  }

  String _fenCacheKey(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 4) return fen;
    return '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
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
    debugPrint(
      '🔧 STREAM SETUP: game ${game.gameId}, index: $index, status: ${game.gameStatus}',
    );

    if (game.gameStatus == GameStatus.ongoing) {
      debugPrint('✅ LISTENER ACTIVE for game ${game.gameId}');
      ref.listen(gameUpdatesStreamProvider(game.gameId), (previous, next) {
        debugPrint('📡 STREAM EVENT for game ${game.gameId}');

        next.whenData((gameData) {
          debugPrint(
            '📦 DATA: game ${game.gameId}, pgn_len=${gameData?['pgn']?.toString().length}, white_clock=${gameData?['last_clock_white']}, black_clock=${gameData?['last_clock_black']}',
          );

          if (gameData != null) {
            final currentState = state.value;
            if (currentState == null) return;

            // Update game data with stream values
            game = game.copyWith(
              pgn: gameData['pgn'] as String? ?? game.pgn,
              fen: gameData['fen'] as String? ?? game.fen,
              lastMove: gameData['last_move'] as String? ?? game.lastMove,
              lastMoveTime:
                  gameData['last_move_time'] != null
                      ? DateTime.tryParse(gameData['last_move_time'] as String)
                      : game.lastMoveTime,
              whiteClockSeconds:
                  (gameData['last_clock_white'] as num?)?.round(),
              blackClockSeconds:
                  (gameData['last_clock_black'] as num?)?.round(),
              gameStatus: _parseGameStatus(
                gameData['status'] as String? ?? '*',
              ),
            );

            // CRITICAL: Update state immediately with new game object to show clock changes
            state = AsyncValue.data(currentState.copyWith(game: game));

            // Reparse moves to show updated position
            _hasParsedMoves = false;
            parseMoves(pgnOverride: game.pgn);
          }
        });
      });
    }
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

      Games? gameWithPgn;
      if (pgn == null || pgn.isEmpty) {
        gameWithPgn = await ref
            .read(gameRepositoryProvider)
            .getGameById(game.gameId);

        if (!mounted) return;

        pgn = gameWithPgn.pgn;
      }

      // Ensure PGN is not empty
      if (pgn == null || pgn.trim().isEmpty) {
        pgn = _getSamplePgnData();
      }

      // Avoid expensive re-parse when nothing changed (e.g. clock-only updates)
      if (currentState != null && currentState.pgnData == pgn) {
        state = AsyncValue.data(
          currentState.copyWith(game: game, isLoadingMoves: false),
        );
        return;
      }

      // Update cached game reference with latest PGN if we fetched it
      if (gameWithPgn != null) {
        game = game.copyWith(
          pgn: gameWithPgn.pgn ?? pgn,
          fen: gameWithPgn.fen ?? game.fen,
          lastMove: gameWithPgn.lastMove ?? game.lastMove,
          lastMoveTime: gameWithPgn.lastMoveTime ?? game.lastMoveTime,
          whiteClockSeconds:
              gameWithPgn.lastClockWhite ?? game.whiteClockSeconds,
          blackClockSeconds:
              gameWithPgn.lastClockBlack ?? game.blackClockSeconds,
        );
      } else {
        game = game.copyWith(pgn: pgn);
      }

      final gameData = PgnGame.parsePgn(pgn);
      final startingPos = PgnGame.startingPosition(gameData.headers);

      Position tempPos = startingPos;
      List<Move> allMoves = [];
      List<String> moveSans = [];

      for (final node in gameData.moves.mainline()) {
        final move = tempPos.parseSan(node.san);
        if (move == null) break;
        allMoves.add(move);
        moveSans.add(node.san);
        tempPos = tempPos.play(move);
      }

      final lastMoveIndex = allMoves.length - 1;
      Move? lastMove;
      Position finalPos = startingPos;
      for (int i = 0; i <= lastMoveIndex; i++) {
        lastMove = allMoves[i];
        finalPos = finalPos.play(allMoves[i]);
      }

      final moveTimes = _parseMoveTimesFromPgn(pgn);

      // Only update state if still mounted
      if (!mounted) return;

      // Check if there are new unseen moves
      final lastSeenMoveCount =
          ref.read(lastSeenMoveCountProvider)[game.gameId] ?? 0;
      final currentMoveCount = moveSans.length;
      final hasNewMoves = currentMoveCount > lastSeenMoveCount;

      // If this is the first time loading the game, mark all moves as seen
      // Otherwise, only mark as unseen if the user is NOT viewing the last move
      final isFirstLoad = lastSeenMoveCount == 0;
      final wasViewingLastMove =
          currentState != null &&
          currentState.allMoves.isNotEmpty &&
          currentState.analysisState.currentMoveIndex ==
              currentState.allMoves.length - 1;
      final shouldMarkAsUnseen =
          hasNewMoves && !isFirstLoad && !wasViewingLastMove;

      // Determine which move index to display:
      // - If first load: ALWAYS jump to last move
      // - If user was viewing last move: jump to new last move
      // - If user was viewing an earlier move AND it's not first load: stay at current position (don't jump)
      final newMoveIndex =
          isFirstLoad
              ? lastMoveIndex // Always show latest on first load
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
                pgnData: pgn,
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
                hasUnseenMoves: shouldMarkAsUnseen,
              )
              : ChessBoardStateNew(
                game: game,
                position: finalPos,
                startingPosition: startingPos,
                lastMove: lastMove,
                allMoves: allMoves,
                moveSans: moveSans,
                currentMoveIndex: newMoveIndex,
                pgnData: pgn,
                isLoadingMoves: false,
                evaluation: null,
                isEvaluating: true,
                isAnalysisMode: true,
                analysisState: AnalysisBoardState(
                  startingPosition: startingPos,
                  currentMoveIndex: newMoveIndex,
                  position: displayPosition,
                  lastMove: displayLastMove,
                  moveSans: moveSans,
                  allMoves: allMoves,
                ),
                moveTimes: moveTimes,
                hasUnseenMoves: shouldMarkAsUnseen,
              );

      state = AsyncValue.data(newState);

      // Update last seen move count if this is the first load
      if (isFirstLoad) {
        _updateLastSeenMoveCount(currentMoveCount);
      }

      // Analysis board is always initialized since analysis mode is always active
      await _initializeAnalysisBoard();

      _updateEvaluation();
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
      debugPrint('Error parsing PGN: $e');
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

  void goToMove(int moveIndex) {
    // Analysis mode is always active, use analysis navigation
    analysisModeGoToMove(moveIndex);
  }

  void analysisModeGoToMove(int moveIndex) {
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
      return;
    }

    if (_isProcessingMove) return;
    _isProcessingMove = true;
    if (currentState.isLoadingMoves) {
      _isProcessingMove = false;
      return;
    }

    if (moveIndex < -1 ||
        moveIndex >= currentState.analysisState.allMoves.length) {
      _isProcessingMove = false;
      return;
    }
    _cancelEvaluation = true;
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
    _updateEvaluation();
    _isProcessingMove = false;
  }

  void normalModeGoToMove(int moveIndex) {
    if (_isProcessingMove) return;
    _isProcessingMove = true;

    final currentState = state.value;
    if (currentState == null || currentState.isLoadingMoves) {
      _isProcessingMove = false;
      return;
    }
    if (moveIndex < -1 || moveIndex >= currentState.allMoves.length) {
      _isProcessingMove = false;
      return;
    }

    _cancelEvaluation = true;

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
    _updateEvaluation();
    _isProcessingMove = false;
  }

  void evaluateCurrentPosition() {
    _updateEvaluation();
  }

  void goToMovePointer(ChessMovePointer pointer) {
    if (_analysisGame == null) return;
    final currentState = state.value;
    if (currentState != null) {
      final cleared = _clearVariantSelection(currentState);
      if (!identical(cleared, currentState)) {
        state = AsyncValue.data(cleared);
      }
    }
    _analysisNavigator?.goToMovePointerUnchecked(pointer);
  }

  void playPrincipalVariationMove(AnalysisLine line) {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.principalVariations.indexOf(line);
    if (index == -1) return;

    debugPrint(
      '🎯 PLAY PV MOVE: index=$index, currentSelected=${currentState.selectedVariantIndex}',
    );

    // If already on this variant, just play forward
    if (currentState.selectedVariantIndex == index) {
      debugPrint('🎯 PLAY PV MOVE: Already selected, playing forward');
      playVariantMoveForward();
      return;
    }

    // Select variant first (this will update the arrows)
    debugPrint('🎯 PLAY PV MOVE: Selecting new variant');
    selectVariant(index);

    // Then play the first move forward
    Future.microtask(() {
      if (mounted && state.value?.selectedVariantIndex == index) {
        playVariantMoveForward();
      }
    });
  }

  /// Select a variant (engine suggestion) for navigation
  void selectVariant(int variantIndex) {
    debugPrint('🎯 SELECT VARIANT: index=$variantIndex');
    final currentState = state.value;
    if (currentState == null) {
      debugPrint('🎯 SELECT VARIANT: FAILED - state null');
      return;
    }
    if (variantIndex < 0 ||
        variantIndex >= currentState.principalVariations.length) {
      debugPrint(
        '🎯 SELECT VARIANT: FAILED - invalid index (pvs=${currentState.principalVariations.length})',
      );
      return;
    }

    // CRITICAL: If same variant already selected, don't reset - just return
    if (currentState.selectedVariantIndex == variantIndex) {
      debugPrint('🎯 SELECT VARIANT: Already selected, skipping re-selection');
      return;
    }

    // CRITICAL: Lock the EXACT current position as the base for this variant exploration
    final baseFen = currentState.analysisState.position.fen;
    final basePointer = currentState.analysisState.movePointer;

    debugPrint(
      '🎯 SELECT VARIANT: Locking base state (fen=$baseFen, pointer=$basePointer)',
    );

    // Show all 3 variants as arrows
    final arrowShapes = _getAllVariantArrowShapes(
      currentState.principalVariations,
      variantIndex,
    );

    final updatedState = currentState.copyWith(
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

    debugPrint('🎯 SELECT VARIANT: Variant selected, base locked');
  }

  /// Play next move of the selected variant forward
  void playVariantMoveForward() {
    debugPrint('🎯 PLAY VARIANT FORWARD called');

    // CRITICAL: Prevent concurrent execution
    if (_isPlayingVariant) {
      debugPrint('🎯 PLAY VARIANT FORWARD: Already playing, skipping');
      return;
    }
    _isPlayingVariant = true;

    try {
      var currentState = state.value;
      if (currentState == null) {
        debugPrint('🎯 PLAY VARIANT FORWARD: State is null');
        return;
      }
      if (!_ensureVariantSelection()) {
        debugPrint('🎯 PLAY VARIANT FORWARD: No variants available');
        return;
      }
      currentState = state.value;
      if (currentState == null || currentState.selectedVariantIndex == null) {
        debugPrint('🎯 PLAY VARIANT FORWARD: Variant selection failed');
        return;
      }

      // CRITICAL: Validate variant navigation is safe
      if (!_isVariantNavigationValid(currentState)) {
        debugPrint(
          '🎯 PLAY VARIANT FORWARD: Variant navigation invalid, clearing stale PVs',
        );
        debugPrint(
          '🎯 PLAY VARIANT FORWARD: New PVs will be calculated for current position',
        );
        // Clear variant selection AND old PVs, then trigger fresh evaluation
        final clearedState = _clearVariantSelection(
          currentState,
        ).copyWith(principalVariations: const [], isEvaluating: true);
        state = AsyncValue.data(clearedState);
        _updateEvaluation(
          force: true,
        ); // Force fresh evaluation for current position
        return;
      }

      if (currentState.variantBaseFen == null) {
        debugPrint('🎯 PLAY VARIANT FORWARD: Missing base FEN, aborting');
        return;
      }

      final selectedVariant =
          currentState.principalVariations[currentState.selectedVariantIndex!];
      final nextMoveIndex = currentState.variantMovePointer.length;

      debugPrint(
        '🎯 PLAY VARIANT FORWARD: nextMoveIndex=$nextMoveIndex, variantLength=${selectedVariant.moves.length}',
      );

      if (nextMoveIndex >= selectedVariant.moves.length) {
        if (!_resumeVariantAutoPlay) {
          debugPrint(
            '🎯 PLAY VARIANT FORWARD: Reached end of variant, requesting extension',
          );
          _resumeVariantAutoPlay = true;
          final currentFen = currentState.analysisState.position.fen;
          final cacheKey = _fenCacheKey(currentFen);
          _pvCache.remove(cacheKey);
          _evaluationCache.remove(cacheKey);
          _mateCache.remove(cacheKey);

          // CRITICAL: Update variant base to CURRENT position for extension
          // The new PVs will start from here, and variantMovePointer resets to []
          final updatedForExtension = currentState.copyWith(
            isEvaluating: true,
            variantBaseFen: currentFen,
            variantBaseMovePointer: currentState.analysisState.movePointer,
            variantMovePointer: const [], // Reset pointer for new base
          );
          state = AsyncValue.data(updatedForExtension);

          debugPrint(
            '🎯 PLAY VARIANT FORWARD: Extension base set to $currentFen, resetting pointer',
          );
          _updateEvaluation(force: true);
        } else {
          debugPrint(
            '🎯 PLAY VARIANT FORWARD: Extension already in progress, waiting',
          );
        }
        return;
      }

      _resumeVariantAutoPlay = false;

      final nextMove = selectedVariant.moves[nextMoveIndex];
      debugPrint('🎯 PLAY VARIANT FORWARD: Next move UCI=${nextMove.uci}');

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
        debugPrint('🎯 PLAY VARIANT FORWARD: Committing move to navigator');
        final (_, san) = currentState.analysisState.position.makeSan(nextMove);

        // Clear variant selection after committing - we're now on mainline
        final clearedState = _clearVariantSelection(currentState);
        state = AsyncValue.data(clearedState);

        // Make move through navigator - this is now the single source of truth
        _analysisNavigator!.makeOrGoToMove(nextMove.uci);
        _playSoundForSan(san);

        // Trigger new evaluation for the new position
        // Cache will be checked first, fresh eval if needed
        _updateEvaluation(force: true);
        return;
      }

      // FALLBACK: Old pointer-based navigation if navigator unavailable
      debugPrint(
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
        debugPrint(
          '🎯 PLAY VARIANT FORWARD: ERROR - Variant moves don\'t match base position',
        );
        debugPrint('   Error: $e');
        debugPrint('   Base FEN: ${currentState.variantBaseFen}');
        debugPrint(
          '   Current FEN: ${currentState.analysisState.position.fen}',
        );
        debugPrint('   Moves to apply: ${newPointer.length}');
        debugPrint(
          '   Variant moves: ${selectedVariant.moves.map((m) => m.uci).join(" ")}',
        );
        debugPrint(
          '🎯 PLAY VARIANT FORWARD: Clearing stale variant and triggering fresh evaluation',
        );
        // Clear stale variant and PVs, trigger fresh evaluation
        final clearedState = _clearVariantSelection(
          currentState,
        ).copyWith(principalVariations: const [], isEvaluating: true);
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

      // Show all variants as arrows
      final arrowShapes = _getAllVariantArrowShapes(
        currentState.principalVariations,
        currentState.selectedVariantIndex!,
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
    debugPrint('🎯 PLAY VARIANT BACKWARD called');
    _resumeVariantAutoPlay = false;
    var currentState = state.value;
    if (currentState == null) {
      debugPrint('🎯 PLAY VARIANT BACKWARD: State is null');
      return;
    }

    // NEW APPROACH: If no active variant pointer, use navigator undo
    // This handles moves that were committed (via forward PV or manual board moves)
    if (currentState.variantMovePointer.isEmpty ||
        currentState.selectedVariantIndex == null) {
      debugPrint(
        '🎯 PLAY VARIANT BACKWARD: No active variant exploration, using navigator undo',
      );
      if (_analysisNavigator != null) {
        final navigatorState = ref.read(
          chessGameNavigatorProvider(_analysisGame!),
        );
        if (navigatorState.movePointer.isNotEmpty) {
          debugPrint('🎯 PLAY VARIANT BACKWARD: Navigator undo available');
          analysisStepBackward();
        } else {
          debugPrint('🎯 PLAY VARIANT BACKWARD: At start of game');
        }
      } else {
        debugPrint('🎯 PLAY VARIANT BACKWARD: Navigator unavailable');
        analysisStepBackward();
      }
      return;
    }

    // OLD APPROACH: Handle pointer-based variant exploration (fallback)
    if (!_ensureVariantSelection()) {
      debugPrint('🎯 PLAY VARIANT BACKWARD: No variants available');
      return;
    }
    currentState = state.value;
    if (currentState == null || currentState.selectedVariantIndex == null) {
      debugPrint('🎯 PLAY VARIANT BACKWARD: Variant selection failed');
      return;
    }

    // CRITICAL: Validate variant navigation is safe
    if (!_isVariantNavigationValid(currentState)) {
      debugPrint(
        '🎯 PLAY VARIANT BACKWARD: Variant navigation invalid, clearing stale PVs',
      );
      debugPrint(
        '🎯 PLAY VARIANT BACKWARD: New PVs will be calculated for current position',
      );
      // Clear variant selection AND old PVs, then trigger fresh evaluation
      final clearedState = _clearVariantSelection(
        currentState,
      ).copyWith(principalVariations: const [], isEvaluating: true);
      state = AsyncValue.data(clearedState);
      _updateEvaluation(
        force: true,
      ); // Force fresh evaluation for current position
      return;
    }

    if (currentState.variantMovePointer.isEmpty) {
      debugPrint(
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

    final arrowShapes = _variantArrowShapes(selectedVariant, newPointer.length);

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

  void moveForward() {
    final currentState = state.value;
    // Bottom nav arrows should navigate within the active context
    // (analysis variation or main game) without forcing a mode change
    if (currentState == null || _isProcessingMove) {
      return;
    }

    final canAdvance =
        currentState.isAnalysisMode
            ? currentState.analysisState.canMoveForward
            : currentState.canMoveForward;

    if (!canAdvance) {
      return;
    }

    if (currentState.isAnalysisMode) {
      analysisStepForward();
      return;
    }

    goToMove(currentState.currentMoveIndex + 1);
  }

  void moveBackward() {
    final currentState = state.value;
    if (currentState == null || _isProcessingMove) {
      return;
    }

    final canRetreat =
        currentState.isAnalysisMode
            ? currentState.analysisState.canMoveBackward
            : currentState.canMoveBackward;

    if (!canRetreat) {
      return;
    }

    if (currentState.isAnalysisMode) {
      analysisStepBackward();
      return;
    }

    goToMove(currentState.currentMoveIndex - 1);
  }

  // REMOVED: toggleAnalysisMode - analysis mode is always active and cannot be toggled

  Future<void> _initializeAnalysisBoard() async {
    final currentState = state.value;
    if (currentState == null) return;

    // Ensure PGN is available
    if (currentState.pgnData == null) {
      await parseMoves();
    }

    final updatedState = state.value;
    if (updatedState == null || updatedState.pgnData == null) {
      return;
    }

    final pgn = updatedState.pgnData!;
    _analysisGame = ChessGame.fromPgn(game.gameId, pgn);

    final storage = ref.read(sharedPreferencesRepository);
    _analysisStateManager = ChessGameNavigatorStateManager(storage: storage);

    final navigator = ref.read(
      chessGameNavigatorProvider(_analysisGame!).notifier,
    );

    // Preserve the current move position when entering analysis mode
    // Move pointer is a single-element array with the current move index
    // For example: if at move 15, pointer should be [15], not [0,1,2,...,15]
    final currentMoveIndex = updatedState.currentMoveIndex;
    final movePointer =
        currentMoveIndex < 0 ? const <int>[] : [currentMoveIndex];

    debugPrint(
      '===== ANALYSIS MODE: Initializing at move index $currentMoveIndex, pointer: $movePointer =====',
    );

    // Set up listener BEFORE replaceState to capture the state change
    _navigatorSubscription?.close();
    _navigatorSubscription = ref.listen<ChessGameNavigatorState>(
      chessGameNavigatorProvider(_analysisGame!),
      (previous, next) {
        debugPrint(
          '===== ANALYSIS MODE: Navigator state changed, movePointer: ${next.movePointer} =====',
        );
        _syncAnalysisFromNavigator(next);
      },
      fireImmediately:
          false, // Don't fire immediately - we'll sync manually after replaceState
    );

    // Always initialize at current position, ignore saved state.
    // Defer to the next microtask to avoid mutating another provider
    // during initialization, which Riverpod asserts against.
    await Future.microtask(() {
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
    debugPrint(
      '🎯 ANALYSIS MOVE: Received move ${move.uci}, isDrop=$isDrop, isPremove=$isPremove',
    );
    debugPrint(
      '🎯 ANALYSIS MOVE: _analysisGame is ${_analysisGame == null ? "null" : "not null"}',
    );
    var currentState = state.value;
    if (currentState == null) {
      debugPrint('🎯 ANALYSIS MOVE: state is null, aborting');
      return;
    }

    final clearedState = _clearVariantSelection(currentState);
    if (!identical(clearedState, currentState)) {
      state = AsyncValue.data(clearedState);
      currentState = clearedState;
    }

    currentState = state.value;
    if (currentState == null) {
      debugPrint('🎯 ANALYSIS MOVE: state missing after clear, aborting');
      return;
    }

    final boardPosition =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position!;

    try {
      if (!boardPosition.isLegal(move)) {
        debugPrint(
          '🎯 ANALYSIS MOVE: ERROR - Move ${move.uci} is ILLEGAL in current board position ${boardPosition.fen}',
        );
        debugPrint('🎯 ANALYSIS MOVE: Turn to move: ${boardPosition.turn}');
        return;
      }
    } catch (e) {
      debugPrint('🎯 ANALYSIS MOVE: ERROR - Failed legality check: $e');
      return;
    }

    if (isPromotionPawnMove(move)) {
      debugPrint('🎯 ANALYSIS MOVE: Promotion detected, storing move');
      debugPrint('🎯 ANALYSIS MOVE: Promotion move UCI: ${move.uci}');
      debugPrint(
        '🎯 ANALYSIS MOVE: Promotion move from: ${move.from}, to: ${move.to}',
      );
      debugPrint(
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
      debugPrint('🎯 ANALYSIS MOVE: Current FEN from navigator: $currentFen');

      if (currentFen == boardPosition.fen) {
        debugPrint(
          '🎯 ANALYSIS MOVE: Navigator aligned, applying move via navigator',
        );
        final (_, san) = boardPosition.makeSan(move);

        _analysisNavigator?.makeOrGoToMove(move.uci);
        _playSoundForSan(san);
        return;
      } else {
        debugPrint(
          '🎯 ANALYSIS MOVE: Navigator FEN differs from board, applying manual fallback',
        );
      }
    } else {
      debugPrint('🎯 ANALYSIS MOVE: _analysisGame is null, using fallback');
    }

    _applyManualAnalysisMove(currentState, boardPosition, move);
  }

  void _applyManualAnalysisMove(
    ChessBoardStateNew currentState,
    Position currentPosition,
    NormalMove move,
  ) {
    try {
      debugPrint('🎯 MANUAL MOVE FALLBACK: Applying move ${move.uci}');

      // CRITICAL: Navigator must be the single source of truth for analysis moves
      // If navigator is out of sync, this is a bug that should not happen
      if (_analysisNavigator == null) {
        debugPrint(
          '🎯 MANUAL MOVE FALLBACK: ERROR - Navigator is null, cannot apply move',
        );
        return;
      }

      final navigatorState = ref.read(
        chessGameNavigatorProvider(_analysisGame!),
      );

      if (navigatorState.currentFen != currentPosition.fen) {
        debugPrint(
          '🎯 MANUAL MOVE FALLBACK: CRITICAL - Navigator out of sync!',
        );
        debugPrint('   Navigator FEN: ${navigatorState.currentFen}');
        debugPrint('   Board FEN: ${currentPosition.fen}');
        debugPrint(
          '   This should not happen - navigator should always match board',
        );
        return;
      }

      // Navigator is in sync, apply move through it
      debugPrint('🎯 MANUAL MOVE FALLBACK: Navigator in sync, applying move');
      _analysisNavigator?.makeOrGoToMove(move.uci);
      return;
    } catch (e) {
      debugPrint('🎯 MANUAL MOVE FALLBACK: ERROR - $e');
      return;
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
        return;
      }

      final pending = state.value?.analysisState.promotionMove;
      if (pending != null) {
        debugPrint('🎯 PROMOTION SELECTION: Pending move UCI: ${pending.uci}');
        debugPrint(
          '🎯 PROMOTION SELECTION: Pending from: ${pending.from}, to: ${pending.to}',
        );
        debugPrint('🎯 PROMOTION SELECTION: Selected role: $role');

        final currentState = state.value!;
        final boardPosition = currentState.analysisState.position;
        final move = pending.withPromotion(role);

        debugPrint(
          '🎯 PROMOTION SELECTION: Final move UCI with promotion: ${move.uci}',
        );
        debugPrint('🎯 PROMOTION SELECTION: Board FEN: ${boardPosition.fen}');

        // Verify navigator is in sync before applying promotion
        if (_analysisNavigator != null) {
          final navigatorState = ref.read(
            chessGameNavigatorProvider(_analysisGame!),
          );
          debugPrint(
            '🎯 PROMOTION SELECTION: Navigator FEN: ${navigatorState.currentFen}',
          );

          if (navigatorState.currentFen == boardPosition.fen) {
            debugPrint(
              '🎯 PROMOTION SELECTION: Navigator in sync, applying via navigator',
            );
            _analysisNavigator?.makeOrGoToMove(move.uci);
          } else {
            debugPrint(
              '🎯 PROMOTION SELECTION: Navigator OUT OF SYNC, using manual fallback',
            );
            // Use manual application as fallback
            _applyManualAnalysisMove(currentState, boardPosition, move);
          }
        } else {
          debugPrint(
            '🎯 PROMOTION SELECTION: No navigator, using manual fallback',
          );
          _applyManualAnalysisMove(currentState, boardPosition, move);
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
    debugPrint('🎯 ANALYSIS STEP FORWARD called');
    if (state.value?.isAnalysisMode != true) {
      debugPrint('🎯 ANALYSIS STEP FORWARD: Not in analysis mode');
      return;
    }
    final currentState = state.value;
    if (currentState == null) return;
    if (_analysisGame == null) {
      debugPrint('🎯 ANALYSIS STEP FORWARD: ERROR - _analysisGame is null');
      return;
    }
    if (_analysisNavigator == null) {
      debugPrint(
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
    debugPrint(
      '🎯 ANALYSIS STEP FORWARD: Current movePointer=${navigatorState.movePointer}',
    );
    debugPrint(
      '🎯 ANALYSIS STEP FORWARD: Current FEN=${navigatorState.currentFen}',
    );
    debugPrint('🎯 ANALYSIS STEP FORWARD: Calling goToNextMove on navigator');
    _analysisNavigator?.goToNextMove();
  }

  /// Navigate backward in analysis mode (through main line when no variant selected)
  void analysisStepBackward() {
    debugPrint('🎯 ANALYSIS STEP BACKWARD called');
    if (state.value?.isAnalysisMode != true) {
      debugPrint('🎯 ANALYSIS STEP BACKWARD: Not in analysis mode');
      return;
    }
    final currentState = state.value;
    if (currentState == null) return;
    if (_analysisGame == null) {
      debugPrint('🎯 ANALYSIS STEP BACKWARD: ERROR - _analysisGame is null');
      return;
    }
    if (_analysisNavigator == null) {
      debugPrint(
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
    debugPrint(
      '🎯 ANALYSIS STEP BACKWARD: Current movePointer=${navigatorState.movePointer}',
    );
    debugPrint(
      '🎯 ANALYSIS STEP BACKWARD: Current FEN=${navigatorState.currentFen}',
    );
    debugPrint(
      '🎯 ANALYSIS STEP BACKWARD: Calling goToPreviousMove on navigator',
    );
    _analysisNavigator?.goToPreviousMove();
  }

  void jumpToStart() {
    debugPrint('🎯 JUMP TO START called');
    final currentState = state.value;
    if (currentState == null) return;

    if (currentState.isAnalysisMode) {
      // Check if variant is selected
      if (currentState.selectedVariantIndex != null) {
        debugPrint(
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
        debugPrint('🎯 JUMP TO START: No variant, jumping to game start');
        _analysisNavigator?.goToHead();
      }
    } else {
      goToMove(-1);
    }
  }

  void jumpToEnd() {
    debugPrint('🎯 JUMP TO END called');
    final currentState = state.value;
    if (currentState == null) return;

    if (currentState.isAnalysisMode) {
      // Check if variant is selected
      if (currentState.selectedVariantIndex != null) {
        debugPrint(
          '🎯 JUMP TO END: Variant selected, playing all variant moves',
        );
        final selectedVariant =
            currentState.principalVariations[currentState
                .selectedVariantIndex!];
        final totalMoves = selectedVariant.moves.length;
        final currentProgress = currentState.variantMovePointer.length;

        debugPrint(
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
        debugPrint('🎯 JUMP TO END: No variant, jumping to game end');
        _analysisNavigator?.goToTail();
      }
    } else {
      goToMove(currentState.allMoves.length - 1);
    }
  }

  void resetGame() {
    if (state.value?.isAnalysisMode == true) {
      _analysisNavigator?.goToHead();
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
  }

  void toggleEngineVisibility() {
    final currentState = state.value;
    if (currentState == null) return;
    state = AsyncValue.data(
      currentState.copyWith(
        showPrincipalVariations: !currentState.showPrincipalVariations,
      ),
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

  Color getMoveColor(String move, int moveIndex) {
    final st = state.value!;
    if (st.isLoadingMoves) {
      return kWhiteColor.withValues(alpha: 0.3);
    }
    if (moveIndex == st.currentMoveIndex - 1) {
      return kWhiteColor;
    }
    if (moveIndex < st.currentMoveIndex - 1) {
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

  Future<List<AnalysisLine>> _buildPrincipalVariations(
    String fen,
    List<Pv> pvs,
  ) async {
    if (pvs.isEmpty) {
      debugPrint('⚠️ BUILD PV: Empty PVs list provided');
      return const [];
    }

    debugPrint('🎯 BUILD PV: Starting with ${pvs.length} PVs for $fen');

    // Validate that at least one PV can be played from this position
    // This catches cases where cached PVs from a different position are being used
    try {
      final testPosition = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(fen),
      );
      bool anyPvValid = false;
      for (final pv in pvs) {
        if (pv.moves.isEmpty) continue;
        final firstMove = pv.moves.split(' ').first;
        final parsed = Move.parse(firstMove);
        if (parsed != null) {
          try {
            testPosition.makeSan(parsed);
            anyPvValid = true;
            break;
          } catch (_) {
            // This PV doesn't work for this position
            continue;
          }
        }
      }
      if (!anyPvValid) {
        debugPrint(
          '⚠️ BUILD PV: No PVs are valid for this FEN - possible cache mismatch',
        );
        return const [];
      }
    } catch (e) {
      debugPrint('⚠️ BUILD PV: FEN validation failed: $e');
      return const [];
    }
    final limitedPvs = pvs.take(_kMaxPrincipalVariations).toList();
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

    List<Map<String, dynamic>> workerResult = const [];
    try {
      workerResult = await workerManager.execute<List<Map<String, dynamic>>>(
        () => _analysisLinesWorker(payload),
        priority: WorkPriority.high,
      );
      debugPrint('🎯 BUILD PV: Worker returned ${workerResult.length} results');
    } catch (e) {
      debugPrint('⚠️ BUILD PV: Worker failed: $e, falling back to main thread');
    }

    if (workerResult.isEmpty) {
      debugPrint('🎯 BUILD PV: Worker result empty, running on main thread');
      workerResult = _analysisLinesWorker(payload);
      if (workerResult.isEmpty) {
        debugPrint('❌ BUILD PV: Main thread also returned empty result');
        return const [];
      }
      debugPrint(
        '🎯 BUILD PV: Main thread returned ${workerResult.length} results',
      );
    }

    final basePosition = Position.setupPosition(
      Rule.chess,
      Setup.parseFen(fen),
    );

    final lines = <AnalysisLine>[];
    for (final entry in workerResult) {
      final uciMoves =
          (entry['uci'] as List<dynamic>? ?? const []).cast<String>();
      final sanMoves =
          (entry['san'] as List<dynamic>? ?? const []).cast<String>();
      final bool isMate = entry['isMate'] == true;
      final mateValue = entry['mate'];
      final cpValue = entry['cp'];

      var position = basePosition;
      final moves = <Move>[];
      var valid = true;

      for (final uci in uciMoves) {
        if (uci.isEmpty) continue;
        final parsedMove = Move.parse(uci);
        if (parsedMove == null) {
          valid = false;
          break;
        }
        try {
          position = position.play(parsedMove);
          moves.add(parsedMove);
        } catch (_) {
          valid = false;
          break;
        }
      }

      if (!valid || moves.isEmpty) continue;

      double? evaluation;
      int? mate;

      if (isMate) {
        mate =
            mateValue is int
                ? mateValue
                : int.tryParse(mateValue?.toString() ?? '');
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

    debugPrint(
      '🎯 BUILD PV: Successfully built ${lines.length} analysis lines',
    );
    if (lines.isEmpty) {
      debugPrint(
        '❌ BUILD PV: No valid lines could be built from ${workerResult.length} worker results',
      );
    }

    // Return actual variations without padding
    // UI will handle displaying 1-3 PV cards dynamically
    debugPrint(
      '✅ BUILD PV: Returning ${lines.length} principal variations (no padding)',
    );

    return lines;
  }

  ChessGameNavigator? get _analysisNavigator =>
      _analysisGame == null
          ? null
          : ref.read(chessGameNavigatorProvider(_analysisGame!).notifier);

  void _playSoundForSan(String san) {
    final audio = AudioPlayerService.instance;
    if (san.contains('#')) {
      audio.player.play(audio.pieceCheckmateSfx);
    } else if (san.contains('+')) {
      audio.player.play(audio.pieceCheckSfx);
    } else if (san == 'O-O' || san == 'O-O-O') {
      audio.player.play(audio.pieceCastlingSfx);
    } else if (san.contains('=')) {
      audio.player.play(audio.piecePromotionSfx);
    } else if (san.contains('x')) {
      audio.player.play(audio.pieceTakeoverSfx);
    } else {
      audio.player.play(audio.pieceMoveSfx);
    }
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
      debugPrint('🎯 VARIANT VALIDATION: No variant base FEN');
      return false;
    }
    if (state.selectedVariantIndex == null) {
      debugPrint('🎯 VARIANT VALIDATION: No variant selected');
      return false;
    }
    if (state.selectedVariantIndex! >= state.principalVariations.length) {
      debugPrint('🎯 VARIANT VALIDATION: Invalid variant index');
      return false;
    }

    final currentFen = state.analysisState.position.fen;
    final baseFen = state.variantBaseFen!;

    // Compare first 3 FEN components (position, turn, castling)
    final currentParts = currentFen.split(' ').take(4).join(' ');
    final baseParts = baseFen.split(' ').take(4).join(' ');

    // If we're at the base position, it's valid
    if (currentParts == baseParts) {
      debugPrint('🎯 VARIANT VALIDATION: At base position - VALID');
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
            testPosition.fen.split(' ').take(4).join(' ') == currentParts;
        debugPrint(
          '🎯 VARIANT VALIDATION: Position reachable from base - ${matches ? "VALID" : "INVALID"}',
        );
        return matches;
      } catch (e) {
        debugPrint('🎯 VARIANT VALIDATION: ERROR calculating position: $e');
        return false;
      }
    }

    // CRITICAL FIX: If pointer is empty, we MUST be at the base position
    // If we're not at base and pointer is empty, the variant base is stale
    // This means PVs were recalculated for a new position
    debugPrint(
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
      final baseFenCompare = previousBaseFen.split(' ').take(4).join(' ');
      final pvFenCompare = baseFen.split(' ').take(4).join(' ');

      if (baseFenCompare != pvFenCompare) {
        debugPrint('🎯 PV RESULTS: REJECTING - PVs for different position');
        debugPrint('   Expected base: $baseFenCompare');
        debugPrint('   PV evaluated from: $pvFenCompare');
        // Keep current state, don't apply these PVs
        return;
      }
    }

    // CRITICAL: Preserve evaluation, mate, and isEvaluating from currentState
    // The caller already set these values and we must NOT reset them
    var nextState = currentState.copyWith(
      principalVariations: pvLines,
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
      final arrowShapes = _getAllVariantArrowShapes(pvLines, 0);
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
        debugPrint(
          '🎯 PV RESULTS: Preserving locked base FEN during variant exploration',
        );
        final arrowShapes = _getAllVariantArrowShapes(
          pvLines,
          previousSelection,
        );
        nextState = nextState.copyWith(
          selectedVariantIndex: previousSelection,
          // Keep the ORIGINAL base FEN, don't update it!
          variantBaseFen: previousBaseFen,
          variantBaseMovePointer: currentState.variantBaseMovePointer,
          variantBaseLastMove: currentState.variantBaseLastMove,
          variantBaseMoveIndex: currentState.variantBaseMoveIndex,
          variantMovePointer: previousVariantPointer,
          shapes: arrowShapes,
        );
      } else {
        // Not in variant exploration - safe to update base
        debugPrint(
          '🎯 PV RESULTS: Not in variant exploration, updating base FEN',
        );

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
            debugPrint(
              '🎯 PV RESULTS: Selected variant no longer valid for new base position',
            );
            debugPrint('   Old base: $previousBaseFen');
            debugPrint('   New base: $baseFen');
            debugPrint('   First move: ${newSelectedVariant.moves.first.uci}');
            variantIsValid = false;
          }
        }

        if (variantIsValid) {
          final arrowShapes = _getAllVariantArrowShapes(
            pvLines,
            previousSelection,
          );
          nextState = nextState.copyWith(
            selectedVariantIndex: previousSelection,
            variantBaseFen: baseFen,
            variantBaseMovePointer: baseMovePointer,
            variantBaseLastMove: currentState.analysisState.lastMove,
            variantBaseMoveIndex: currentState.analysisState.currentMoveIndex,
            variantMovePointer: const [],
            shapes: arrowShapes,
          );
        } else {
          // Variant is invalid, clear selection
          debugPrint('🎯 PV RESULTS: Clearing invalid variant selection');
          nextState = _clearVariantSelection(nextState);
        }
      }
    } else {
      nextState = _clearVariantSelection(nextState);
    }

    _resumeVariantAutoPlay = false;
    state = AsyncValue.data(nextState);

    // CRITICAL FIX: Auto-resume variant playback if we were waiting for extension
    if (shouldResumeAutoPlay &&
        nextState.selectedVariantIndex != null &&
        nextState.selectedVariantIndex! < pvLines.length) {
      final newVariant = pvLines[nextState.selectedVariantIndex!];

      debugPrint(
        '🎯 AUTO-RESUME: Extension completed, newVariantLength=${newVariant.moves.length}',
      );

      // After extension, variantMovePointer was reset to []
      // and variantBaseFen was updated to current position
      // So we can start playing from index 0 of the new variant
      if (newVariant.moves.isNotEmpty) {
        debugPrint(
          '🎯 AUTO-RESUME: New PVs available, resuming playback from new base',
        );
        // Use Future.microtask to avoid calling during build
        Future.microtask(() {
          if (mounted && state.value?.selectedVariantIndex != null) {
            playVariantMoveForward();
          }
        });
      } else {
        debugPrint(
          '🎯 AUTO-RESUME: No moves in extended variant - game may be over',
        );
      }
    }
  }

  int _calculateVariantProgress(
    String baseFen,
    List<Move> moves,
    String currentFen,
  ) {
    try {
      var position = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(baseFen),
      );
      if (position.fen == currentFen) return 0;

      for (int i = 0; i < moves.length; i++) {
        position = position.play(moves[i]);
        if (position.fen == currentFen) {
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
    var position = Position.setupPosition(Rule.chess, Setup.parseFen(baseFen));

    for (int i = 0; i < movesToApply && i < variant.moves.length; i++) {
      position = position.play(variant.moves[i]);
    }

    return position;
  }

  Future<void> _evaluatePosition({bool force = false}) async {
    int? requestId;
    try {
      final initialState = state.value;
      if (initialState == null || initialState.isLoadingMoves) return;

      final fen =
          initialState.isAnalysisMode
              ? initialState.analysisState.position.fen
              : initialState.position?.fen;
      if (fen == null) return;

      final cacheKey = _fenCacheKey(fen);

      final cachedEval = _evaluationCache[cacheKey];
      final cachedPv = _pvCache[cacheKey];
      final cachedMate = _mateCache[cacheKey];
      if (!force &&
          cachedEval != null &&
          cachedPv != null &&
          cachedPv.isNotEmpty) {
        var cachedState = initialState.copyWith(
          evaluation: cachedEval,
          mate: cachedMate ?? initialState.mate,
          isEvaluating: false,
        );
        state = AsyncValue.data(cachedState);

        final basePointer =
            cachedState.isAnalysisMode
                ? cachedState.analysisState.movePointer
                : null;
        final position =
            cachedState.isAnalysisMode
                ? cachedState.analysisState.position
                : cachedState.position!;

        _applyPrincipalVariationResults(
          currentState: cachedState,
          currentPosition: position,
          baseFen: fen,
          baseMovePointer: basePointer,
          pvLines: cachedPv,
        );
        return;
      }

      if (!force &&
          _activeEvalKey == cacheKey &&
          _activeEvalRequestId != null) {
        debugPrint(
          '🎯 EVAL: Skipping duplicate request for $cacheKey (already running)',
        );
        return;
      }

      final currentRequestId = requestId = ++_evalRequestCounter;
      _activeEvalKey = cacheKey;
      _activeEvalRequestId = currentRequestId;

      state = AsyncValue.data(
        initialState.copyWith(shapes: const ISet.empty(), isEvaluating: true),
      );

      CloudEval? primaryEval;
      double? evaluation;
      List<AnalysisLine> pvLines = const [];

      debugPrint('🎯 EVAL START: Evaluating position $fen');

      // OPTIMIZED: Try cascade (cloud sources) FIRST for speed
      // Cascade queries local DB, Supabase, and Lichess in parallel
      try {
        debugPrint(
          '🎯 EVAL: Requesting cascade evaluation (parallel cloud sources)...',
        );
        final cascadeEval = await ref.read(
          cascadeEvalProviderForBoard(fen).future,
        );
        if (cascadeEval.pvs.isNotEmpty) {
          primaryEval = cascadeEval;
          evaluation = _getConsistentEvaluation(
            cascadeEval.pvs.first.cp / 100.0,
            fen,
          );
          debugPrint(
            '🎯 EVAL: Building principal variations from cloud source...',
          );
          pvLines = await _buildPrincipalVariations(fen, cascadeEval.pvs);

          // RETRY: If cloud PV building failed but we have PVs, try once more
          if (pvLines.isEmpty && cascadeEval.pvs.isNotEmpty) {
            debugPrint(
              '🔄 RETRY: Cloud PV building failed, retrying after 200ms...',
            );
            await Future.delayed(const Duration(milliseconds: 200));

            // Check if position changed during the delay
            final currentState = state.value;
            if (currentState != null) {
              final currentPos =
                  currentState.isAnalysisMode
                      ? currentState.analysisState.position
                      : currentState.position;
              if (currentPos != null) {
                final currentFenBase = currentPos.fen
                    .split(' ')
                    .take(4)
                    .join(' ');
                final targetFenBase = fen.split(' ').take(4).join(' ');

                if (currentFenBase != targetFenBase) {
                  debugPrint(
                    '🚫 RETRY CANCELLED: Position changed during delay (was: $targetFenBase, now: $currentFenBase)',
                  );
                  return;
                }
              }
            }

            pvLines = await _buildPrincipalVariations(fen, cascadeEval.pvs);
            if (pvLines.isNotEmpty) {
              debugPrint('✅ RETRY: Cloud PV building succeeded on retry');
            } else {
              debugPrint(
                '❌ RETRY: Cloud PV building failed again, will try Stockfish',
              );
            }
          }

          debugPrint(
            '🎯 EVAL: CASCADE SUCCESS - returned ${pvLines.length} variants from ${cascadeEval.pvs.length} cloud PVs, eval=$evaluation',
          );
        } else {
          debugPrint('🎯 EVAL: Cascade returned empty PVs');
        }
      } catch (e) {
        debugPrint('🎯 EVAL ERROR: Cascade failed for $fen: $e');
      }

      // SUPPLEMENT/FALLBACK: Use Stockfish if cloud sources returned < 3 PVs
      // Cloud sources (Lichess multiPv=3) should usually return 3 PVs, but might return fewer for:
      // - Uncommon positions not yet fully analyzed
      // - Positions with forced mates (only one line matters)
      // - API rate limiting or temporary unavailability
      if (evaluation == null || pvLines.length < 3) {
        final needsEval = evaluation == null;
        final needsMorePvs = pvLines.length < 3;

        try {
          debugPrint(
            '🎯 EVAL: Need ${needsEval ? "eval + " : ""}${needsMorePvs ? "more PVs (have ${pvLines.length}/3)" : ""}, running Stockfish...',
          );
          final localEval = await StockfishSingleton().evaluatePosition(
            fen,
            depth: _resumeVariantAutoPlay ? 12 : 15,
          );
          debugPrint(
            '🎯 EVAL: Stockfish completed, isCancelled=${localEval.isCancelled}, pvs.length=${localEval.pvs.length}',
          );

          if (!localEval.isCancelled && localEval.pvs.isNotEmpty) {
            // Use Stockfish eval if we don't have one from cloud
            if (needsEval) {
              primaryEval = CloudEval(
                fen: fen,
                knodes: localEval.knodes,
                depth: localEval.depth,
                pvs: localEval.pvs,
              );
              evaluation = _getConsistentEvaluation(
                localEval.pvs.first.cp / 100.0,
                fen,
              );
            }

            // Build PVs from Stockfish with retry on failure
            debugPrint(
              '🎯 EVAL: Building principal variations from Stockfish MultiPV...',
            );
            var stockfishPvLines = await _buildPrincipalVariations(
              fen,
              localEval.pvs,
            );

            // RETRY: If Stockfish PV building failed, try once more after a small delay
            if (stockfishPvLines.isEmpty && localEval.pvs.isNotEmpty) {
              debugPrint(
                '🔄 RETRY: Stockfish PV building failed, retrying after 200ms...',
              );
              await Future.delayed(const Duration(milliseconds: 200));

              // Check if position changed during the delay
              final currentState = state.value;
              if (currentState != null) {
                final currentPos =
                    currentState.isAnalysisMode
                        ? currentState.analysisState.position
                        : currentState.position;
                if (currentPos != null) {
                  final currentFenBase = currentPos.fen
                      .split(' ')
                      .take(4)
                      .join(' ');
                  final targetFenBase = fen.split(' ').take(4).join(' ');

                  if (currentFenBase != targetFenBase) {
                    debugPrint(
                      '🚫 RETRY CANCELLED: Position changed during delay (was: $targetFenBase, now: $currentFenBase)',
                    );
                    return;
                  }
                }
              }

              stockfishPvLines = await _buildPrincipalVariations(
                fen,
                localEval.pvs,
              );
              if (stockfishPvLines.isNotEmpty) {
                debugPrint('✅ RETRY: Stockfish PV building succeeded on retry');
              } else {
                debugPrint('❌ RETRY: Stockfish PV building failed again');
              }
            }

            // Merge: Keep cloud PVs first, then add unique Stockfish PVs
            if (needsMorePvs && pvLines.isNotEmpty) {
              final merged = <AnalysisLine>[...pvLines];
              final existingFirstMoves =
                  pvLines
                      .map(
                        (line) =>
                            line.sanMoves.isNotEmpty ? line.sanMoves.first : '',
                      )
                      .toSet();

              for (final sfLine in stockfishPvLines) {
                if (merged.length >= 3) break;
                final firstMove =
                    sfLine.sanMoves.isNotEmpty ? sfLine.sanMoves.first : '';
                // Add if it's a different first move (different principal variation)
                if (!existingFirstMoves.contains(firstMove)) {
                  merged.add(sfLine);
                  existingFirstMoves.add(firstMove);
                }
              }
              pvLines = merged;
              debugPrint(
                '🎯 EVAL: MERGED - ${pvLines.length} variants (cloud + Stockfish)',
              );
            } else {
              // No cloud PVs, use all Stockfish PVs
              pvLines = stockfishPvLines;
              debugPrint(
                '🎯 EVAL: STOCKFISH ONLY - returned ${pvLines.length} variants, eval=$evaluation',
              );
            }
          } else {
            debugPrint('🎯 EVAL: Stockfish returned cancelled or empty result');
          }
        } catch (e, stack) {
          debugPrint('🎯 EVAL ERROR: Stockfish supplement failed for $fen: $e');
          debugPrint('Stack: $stack');
        }
      }

      // CRITICAL FIX: Show evaluation even if PVs fail to convert
      // During live games with rapid moves, PV conversion might fail due to race conditions,
      // but we still want to show the evaluation bar and prevent stuck loading state
      if (evaluation == null || primaryEval == null) {
        debugPrint('❌ EVAL FAILED: No valid evaluation available for $fen');
        debugPrint(
          '   evaluation=$evaluation, pvLines.length=${pvLines.length}, primaryEval=$primaryEval',
        );
        final fallbackState = state.value;
        if (fallbackState != null) {
          // Set a default evaluation to prevent stuck loading state
          state = AsyncValue.data(
            fallbackState.copyWith(
              isEvaluating: false,
              evaluation: 0.0,
              principalVariations: const [],
            ),
          );
        }
        return;
      }

      // If we have evaluation but no PVs, still proceed - show eval bar without PV cards
      // BUT: Schedule a retry for the current visible position to get PVs
      if (pvLines.isEmpty && primaryEval.pvs.isNotEmpty) {
        debugPrint(
          '⚠️ EVAL: Have evaluation ($evaluation) but PV conversion failed - will retry',
        );
        debugPrint('   primaryEval?.pvs.length=${primaryEval.pvs.length}');
        debugPrint(
          '   ⚠️ PRIMARY EVAL HAS PVS BUT pvLines IS EMPTY - possible FEN mismatch, scheduling retry',
        );
        debugPrint(
          '   First PV: moves=${primaryEval.pvs.first.moves}, cp=${primaryEval.pvs.first.cp}',
        );

        // Schedule retry after a short delay to let position stabilize
        // This handles race conditions during rapid live game moves
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted || _cancelEvaluation) return;
          final currentState = state.value;
          if (currentState == null) return;

          // Check if we're still on the same position
          final currentPos =
              currentState.isAnalysisMode
                  ? currentState.analysisState.position
                  : currentState.position;
          if (currentPos == null) return;

          final currentFenBase = currentPos.fen.split(' ').take(4).join(' ');
          final targetFenBase = fen.split(' ').take(4).join(' ');

          // Only retry if still on same position and still no PVs
          if (currentFenBase == targetFenBase &&
              currentState.principalVariations.isEmpty &&
              !currentState.isEvaluating) {
            debugPrint(
              '🔄 RETRY: Re-evaluating position to get PVs (target: $targetFenBase)',
            );
            _evaluatePosition();
          }
        });
        // Continue with empty PVs - we still want to show the evaluation
      } else if (pvLines.isEmpty) {
        debugPrint(
          '⚠️ EVAL: No PVs available and primaryEval has no PVs either',
        );
      }

      // OPTIMIZATION: Don't await cache persistence - run in background for speed
      // User sees evaluation immediately while caching happens asynchronously
      final cache = ref.read(localEvalCacheProvider);
      final persist = ref.read(persistCloudEvalProvider);
      Future.wait([
        persist.call(fen, primaryEval),
        cache.save(fen, primaryEval),
      ]).catchError((e) {
        debugPrint('Background persist failed for $fen: $e');
        return <void>[];
      });

      if (_cancelEvaluation || state.value == null || !mounted) return;
      if (_activeEvalRequestId != currentRequestId) return;
      var currentSnapshot = state.value;
      if (currentSnapshot == null) return;

      final inAnalysis = currentSnapshot.isAnalysisMode;
      final position =
          inAnalysis
              ? currentSnapshot.analysisState.position
              : currentSnapshot.position!;

      // Allow small FEN differences (like move counters) during variant exploration
      final currentFenBase = position.fen.split(' ').take(4).join(' ');
      final evalFenBase = fen.split(' ').take(4).join(' ');

      if (currentFenBase != evalFenBase) {
        debugPrint(
          '🎯 EVAL: Position changed during eval (current=$currentFenBase vs eval=$evalFenBase)',
        );
        debugPrint(
          '🎯 EVAL: Caching result for $evalFenBase but not applying to current position',
        );

        // CRITICAL: Still cache the evaluation result even if position changed
        // This prevents wasted computation and speeds up navigation
        _evaluationCache[cacheKey] = evaluation;
        _mateCache[cacheKey] =
            primaryEval.pvs.first.mate ?? currentSnapshot.mate;
        _pvCache[cacheKey] = pvLines;

        // EDGE CASE FIX: Check if we have cached evaluation for the CURRENT position
        // This handles race conditions where evaluation completes after position changed
        // but the new position already has a cached result available
        final currentPositionFen = position.fen;
        final currentCacheKey = _fenCacheKey(currentPositionFen);
        final cachedCurrentEval = _evaluationCache[currentCacheKey];
        final cachedCurrentPv = _pvCache[currentCacheKey];
        final cachedCurrentMate = _mateCache[currentCacheKey];

        if (cachedCurrentEval != null &&
            cachedCurrentPv != null &&
            cachedCurrentPv.isNotEmpty) {
          // Apply cached evaluation for current position to prevent stuck loading state
          debugPrint(
            '🎯 EVAL: Applying cached result for current position to prevent loading state',
          );
          final basePointer =
              inAnalysis ? currentSnapshot.analysisState.movePointer : null;

          final inVariantExploration =
              currentSnapshot.selectedVariantIndex != null &&
              currentSnapshot.variantMovePointer.isNotEmpty &&
              currentSnapshot.variantBaseFen != null;

          final ISet<Shape> shapes;
          if (currentSnapshot.selectedVariantIndex != null &&
              cachedCurrentPv.isNotEmpty) {
            shapes = _getAllVariantArrowShapes(
              cachedCurrentPv,
              currentSnapshot.selectedVariantIndex!,
            );
          } else {
            final evalForShapes = CloudEval(
              fen: currentPositionFen,
              knodes: 0,
              depth: 0,
              pvs:
                  cachedCurrentPv
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
            );
            shapes = getBestMoveShape(position, evalForShapes);
          }

          final updatedState = currentSnapshot.copyWith(
            evaluation: cachedCurrentEval,
            mate: cachedCurrentMate ?? currentSnapshot.mate,
            isEvaluating: false,
            shapes: shapes,
            principalVariations: cachedCurrentPv,
            variantBaseFen:
                inVariantExploration
                    ? currentSnapshot.variantBaseFen
                    : currentPositionFen,
            variantBaseMovePointer:
                inVariantExploration
                    ? currentSnapshot.variantBaseMovePointer
                    : basePointer,
            analysisState: currentSnapshot.analysisState.copyWith(
              suggestionLines: cachedCurrentPv,
            ),
          );
          state = AsyncValue.data(updatedState);

          _applyPrincipalVariationResults(
            currentState: updatedState,
            currentPosition: position,
            baseFen: currentPositionFen,
            baseMovePointer: basePointer,
            pvLines: cachedCurrentPv,
          );
        } else {
          // No cached result for current position - just turn off evaluating flag
          state = AsyncValue.data(
            currentSnapshot.copyWith(isEvaluating: false),
          );
        }
        return;
      }

      final basePointer =
          inAnalysis ? currentSnapshot.analysisState.movePointer : null;
      final mateScore = primaryEval.pvs.first.mate ?? currentSnapshot.mate;

      _evaluationCache[cacheKey] = evaluation;
      _mateCache[cacheKey] = mateScore;
      _pvCache[cacheKey] = pvLines;

      // CRITICAL: Don't overwrite variant base if we're exploring a variant
      final inVariantExploration =
          currentSnapshot.selectedVariantIndex != null &&
          currentSnapshot.variantMovePointer.isNotEmpty &&
          currentSnapshot.variantBaseFen != null;

      // CRITICAL: Use multi-variant arrows if variant selected, otherwise use best move
      final ISet<Shape> shapes;
      if (currentSnapshot.selectedVariantIndex != null && pvLines.isNotEmpty) {
        shapes = _getAllVariantArrowShapes(
          pvLines,
          currentSnapshot.selectedVariantIndex!,
        );
      } else {
        shapes = getBestMoveShape(position, primaryEval);
      }

      currentSnapshot = currentSnapshot.copyWith(
        evaluation: evaluation,
        mate: mateScore,
        isEvaluating: false,
        shapes: shapes,
        principalVariations: pvLines,
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

      // Note: Removed supplemental eval since Stockfish is now primary with MultiPV=3
    } catch (e) {
      if (!_cancelEvaluation) {
        debugPrint('Evaluation error: $e');
      }
      final fallbackState = state.value;
      if (fallbackState != null) {
        state = AsyncValue.data(fallbackState.copyWith(isEvaluating: false));
      }
    } finally {
      if (requestId != null && _activeEvalRequestId == requestId) {
        _activeEvalRequestId = null;
        _activeEvalKey = null;
      }
    }
  }

  void _syncAnalysisFromNavigator(ChessGameNavigatorState navigatorState) {
    final current = state.value;
    if (current == null) {
      return;
    }

    try {
      final position = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(navigatorState.currentFen),
      );

      Move? lastMove;
      final currentMove = navigatorState.currentMove;
      if (currentMove != null) {
        final parsed = Move.parse(currentMove.uci);
        if (parsed != null) {
          lastMove = parsed;
        }
      }

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
              const [], // Clear stale PV arrows until new evaluation completes
        ),
        evaluation: null,
        isEvaluating: true,
      );

      var progressedState = _setVariantProgress(
        currentState: nextState,
        currentPosition: position,
      );

      state = AsyncValue.data(progressedState);

      if (!_cancelEvaluation) {
        _updateEvaluation();
      }
    } catch (e) {
      debugPrint('Failed to sync analysis navigator state: $e');
    }
  }

  ISet<Shape> getBestMoveShape(Position pos, CloudEval? cloudEval) {
    ISet<Shape> shapes = const ISet.empty();
    if (cloudEval?.pvs.isNotEmpty ?? false) {
      final arrowShapes = <Arrow>[];

      // CRITICAL: Validate that the PVs are for the correct position
      // The cloudEval.fen should match the position we're displaying arrows for
      if (cloudEval!.fen != pos.fen) {
        debugPrint('⚠️ PV ARROWS: Skipping - PVs are for different position');
        debugPrint('   Current FEN: ${pos.fen}');
        debugPrint('   Eval FEN: ${cloudEval.fen}');
        return const ISet.empty();
      }

      // Get up to [_kMaxPrincipalVariations] principal variations
      final pvsToShow = cloudEval.pvs.take(_kMaxPrincipalVariations).toList();

      for (int i = 0; i < pvsToShow.length; i++) {
        final pv = pvsToShow[i];
        String bestMove =
            pv.moves.split(" ")[0].toLowerCase(); // Normalize to lowercase

        if (bestMove.length < 4 || bestMove.length > 5) {
          debugPrint('Invalid best move UCI: $bestMove');
          continue; // Skip invalid UCI
        }

        try {
          // Use different colors/opacity for primary, secondary, tertiary moves
          final arrowColor = switch (i) {
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
              debugPrint(
                '⚠️ PV ARROWS: Move $bestMove is not legal for position (turn: ${pos.turn})',
              );
              continue; // Skip illegal moves
            }

            arrowShapes.add(Arrow(color: arrowColor, orig: from, dest: to));
          }
        } catch (e) {
          // Parsing failed for this PV, continue with next
          debugPrint('Error parsing PV $i best move UCI: $e');
          continue;
        }
      }

      if (arrowShapes.isNotEmpty) {
        shapes = arrowShapes.toISet();
      }
    } else {
      debugPrint('No evaluation data available.');
    }
    return shapes;
  }

  ISet<Shape> _variantArrowShapes(AnalysisLine variant, int nextMoveIndex) {
    if (nextMoveIndex < 0 || nextMoveIndex >= variant.moves.length) {
      return const ISet.empty();
    }
    final move = variant.moves[nextMoveIndex];
    if (move is! NormalMove) {
      return const ISet.empty();
    }
    try {
      final arrow = Arrow(
        color: kPrimaryColor.withValues(alpha: 0.8),
        orig: move.from,
        dest: move.to,
      );
      return [arrow].toISet();
    } catch (_) {
      return const ISet.empty();
    }
  }

  /// Show all 3 variant first moves as arrows with different opacity
  /// Stable variant colors - always in this order regardless of evaluations
  static const List<Color> _variantColors = [
    Color.fromARGB(180, 152, 179, 154), // Green - Always 1st variant
    Color.fromARGB(180, 100, 149, 237), // Blue - Always 2nd variant
    Color.fromARGB(180, 255, 165, 0), // Orange - Always 3rd variant
  ];

  /// Get color for a variant index (used for both arrows and card borders)
  /// Always returns the static variant color (Green/Blue/Orange)
  /// Selection is indicated by higher opacity, not different color
  Color getVariantColor(int variantIndex, bool isSelected) {
    if (variantIndex >= 0 && variantIndex < _variantColors.length) {
      // Use static variant color, adjust opacity for selection
      return _variantColors[variantIndex].withValues(
        alpha: isSelected ? 0.95 : 0.7,
      );
    }
    return const Color.fromARGB(100, 152, 179, 154);
  }

  ISet<Shape> _getAllVariantArrowShapes(
    List<AnalysisLine> variants,
    int selectedIndex,
  ) {
    final arrows = <Arrow>[];

    for (int i = 0; i < variants.length && i < 3; i++) {
      final variant = variants[i];
      if (variant.moves.isEmpty) continue;

      final move = variant.moves[0];
      if (move is! NormalMove) continue;

      try {
        final arrowColor = getVariantColor(i, i == selectedIndex);

        arrows.add(Arrow(color: arrowColor, orig: move.from, dest: move.to));
      } catch (_) {
        continue;
      }
    }

    return arrows.toISet();
  }

  void _updateEvaluation({bool force = false}) {
    if (_isLongPressing) return;

    // CRITICAL: Cancel any pending debounced evaluation first
    EasyDebounce.cancel('evaluation-$index');

    _cancelEvaluation = false;
    if (force) {
      _activeEvalKey = null;
      _activeEvalRequestId = null;
    }

    // CRITICAL: Clear stale PVs immediately when position changes
    final currentState = state.value;
    if (currentState != null && currentState.principalVariations.isNotEmpty) {
      final fenToEval =
          currentState.isAnalysisMode
              ? currentState.analysisState.position.fen
              : currentState.position?.fen;

      // Check if current PVs match the position we're about to evaluate
      // Use variantBaseFen which tracks the position PVs were calculated for
      if (currentState.variantBaseFen != null && fenToEval != null) {
        final pvFenBase = currentState.variantBaseFen!
            .split(' ')
            .take(4)
            .join(' ');
        final currentFenBase = fenToEval.split(' ').take(4).join(' ');

        if (pvFenBase != currentFenBase) {
          debugPrint('🎯 UPDATE EVAL: Clearing stale PVs for new position');
          state = AsyncValue.data(
            currentState.copyWith(
              principalVariations: const [],
              selectedVariantIndex: null,
              variantBaseFen: null,
              variantMovePointer: const [],
            ),
          );
        }
      }
    }

    // CRITICAL FIX: Start evaluation immediately without debounce
    // The debounce was causing evaluations to be cancelled during rapid navigation
    if (!_cancelEvaluation && state.value != null && mounted) {
      debugPrint(
        '🎯 EVAL: Starting evaluation immediately for current position',
      );
      _evaluatePosition(force: force);
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
                ? currentState!.analysisState.canMoveForward
                : currentState?.canMoveForward == true;
        if (canAdvance && !_isProcessingMove) {
          // Light haptic feedback on each step
          HapticFeedback.selectionClick();
          moveForward();
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
                ? currentState!.analysisState.canMoveBackward
                : currentState?.canMoveBackward == true;
        if (canRetreat && !_isProcessingMove) {
          // Light haptic feedback on each step
          HapticFeedback.selectionClick();
          moveBackward();
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
    _evaluationCache.clear();
    _mateCache.clear();
    _pvCache.clear();
    unawaited(_persistAnalysisState());
    _navigatorSubscription?.close();
    _navigatorSubscription = null;
    super.dispose();
  }
}

// Provider parameter to pass game directly instead of fetching from global provider
class ChessBoardProviderParams {
  final GamesTourModel game;
  final int index;

  const ChessBoardProviderParams({required this.game, required this.index});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessBoardProviderParams &&
          runtimeType == other.runtimeType &&
          game.gameId == other.game.gameId &&
          index == other.index;

  @override
  int get hashCode => game.gameId.hashCode ^ index.hashCode;
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
          debugPrint(
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
          debugPrint('⚠️ UCI->SAN failed: "$token" on ${position.fen}');
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
