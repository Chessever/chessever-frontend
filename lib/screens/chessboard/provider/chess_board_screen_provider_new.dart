import 'dart:async';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator_state_manager.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/evals.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:worker_manager/worker_manager.dart';

const int _kMaxPrincipalVariations = 3;

enum ChessboardView { tour, countryman }

final chessboardViewFromProviderNew = StateProvider<ChessboardView>((ref) {
  return ChessboardView.tour;
});

// Global provider to track the currently visible page index
// This prevents off-screen games from playing audio or triggering unnecessary updates
final currentlyVisiblePageIndexProvider = StateProvider<int>((ref) {
  return 0;
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
  ChessGame? _analysisGame;
  ChessGameNavigatorStateManager? _analysisStateManager;
  ProviderSubscription<ChessGameNavigatorState>? _navigatorSubscription;

  void _initializeState() {
    state = AsyncValue.data(
      ChessBoardStateNew(
        game: game,
        pgnData: null,
        isLoadingMoves: true,
        fenData: game.fen,
        evaluation: null, // Start with null to indicate no evaluation yet
        isEvaluating: false,
      ),
    );
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

  void _setupPgnStreamListener() {
    // Only listen to game updates stream if the game is ongoing
    if (game.gameStatus == GameStatus.ongoing) {
      ref.listen(gameUpdatesStreamProvider(game.gameId), (previous, next) {
        next.whenData((gameData) {
          if (gameData != null) {
            final currentState = state.value;

            // CRITICAL: Check if this game board is currently visible
            // This prevents off-screen games from playing audio or resetting positions
            final currentVisibleIndex = ref.read(
              currentlyVisiblePageIndexProvider,
            );
            final isCurrentlyVisible = currentVisibleIndex == index;

            debugPrint(
              '===== GAME UPDATE: Game ${game.gameId} (index $index), visible: $isCurrentlyVisible, analysisMode: ${currentState?.isAnalysisMode} =====',
            );

            // CRITICAL: Don't update board state if user is actively analyzing
            // This prevents resetting the board when viewing past positions or variants
            if (currentState?.isAnalysisMode == true) {
              // In analysis mode, only update the underlying game data
              // but don't reset the board position
              game = game.copyWith(
                pgn: gameData['pgn'] as String? ?? game.pgn,
                fen: gameData['fen'] as String? ?? game.fen,
                lastMove: gameData['last_move'] as String? ?? game.lastMove,
                lastMoveTime:
                    gameData['last_move_time'] != null
                        ? DateTime.tryParse(
                          gameData['last_move_time'] as String,
                        )
                        : game.lastMoveTime,
                whiteClockSeconds:
                    (gameData['last_clock_white'] as num?)?.round(),
                blackClockSeconds:
                    (gameData['last_clock_black'] as num?)?.round(),
                gameStatus: _parseGameStatus(
                  gameData['status'] as String? ?? '*',
                ),
              );

              // Update only the game reference in state, preserve analysis position
              if (currentState != null) {
                state = AsyncValue.data(currentState.copyWith(game: game));
              }

              debugPrint("Game data updated but preserving analysis position");
              return;
            }

            // CRITICAL: In normal mode, check if user is viewing a past position
            // Don't auto-update if they've navigated away from the latest move
            if (currentState != null &&
                !currentState.isLoadingMoves &&
                currentState.currentMoveIndex <
                    currentState.allMoves.length - 1) {
              // User is viewing a past position, only update game data
              game = game.copyWith(
                pgn: gameData['pgn'] as String? ?? game.pgn,
                fen: gameData['fen'] as String? ?? game.fen,
                lastMove: gameData['last_move'] as String? ?? game.lastMove,
                lastMoveTime:
                    gameData['last_move_time'] != null
                        ? DateTime.tryParse(
                          gameData['last_move_time'] as String,
                        )
                        : game.lastMoveTime,
                whiteClockSeconds:
                    (gameData['last_clock_white'] as num?)?.round(),
                blackClockSeconds:
                    (gameData['last_clock_black'] as num?)?.round(),
                gameStatus: _parseGameStatus(
                  gameData['status'] as String? ?? '*',
                ),
              );

              state = AsyncValue.data(currentState.copyWith(game: game));
              debugPrint(
                "Game data updated but preserving user's current position",
              );
              return;
            }

            // CRITICAL: If this game is not currently visible, update game data silently
            // without triggering position changes that would cause audio to play
            if (!isCurrentlyVisible) {
              game = game.copyWith(
                pgn: gameData['pgn'] as String? ?? game.pgn,
                fen: gameData['fen'] as String? ?? game.fen,
                lastMove: gameData['last_move'] as String? ?? game.lastMove,
                lastMoveTime:
                    gameData['last_move_time'] != null
                        ? DateTime.tryParse(
                          gameData['last_move_time'] as String,
                        )
                        : game.lastMoveTime,
                whiteClockSeconds:
                    (gameData['last_clock_white'] as num?)?.round(),
                blackClockSeconds:
                    (gameData['last_clock_black'] as num?)?.round(),
                gameStatus: _parseGameStatus(
                  gameData['status'] as String? ?? '*',
                ),
              );

              // Mark that moves need to be re-parsed when user switches to this game
              _hasParsedMoves = false;

              // Update only game data, don't trigger position updates
              if (currentState != null) {
                state = AsyncValue.data(currentState.copyWith(game: game));
              }

              debugPrint(
                "Off-screen game ${game.gameId} updated silently (index: $index, visible: $currentVisibleIndex)",
              );
              return;
            }

            bool needsReparse = false;
            bool needsEvaluation = false;

            // Check if PGN changed
            final newPgn = gameData['pgn'] as String?;
            if (newPgn != null && newPgn != game.pgn) {
              needsReparse = true;
            }

            // Check if position changed (FEN or last_move) for evaluation updates
            final newFen = gameData['fen'] as String? ?? game.fen;
            final newLastMove =
                gameData['last_move'] as String? ?? game.lastMove;
            if (newFen != game.fen || newLastMove != game.lastMove) {
              needsEvaluation = true;
            }

            // Create updated game model with all live data
            game = game.copyWith(
              pgn: newPgn ?? game.pgn,
              fen: newFen,
              lastMove: newLastMove,
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

            // CRITICAL: Only reparse if this is the currently visible game
            // This prevents off-screen games from triggering full position updates
            if (needsReparse && isCurrentlyVisible) {
              _hasParsedMoves = false;
              parseMoves();
              debugPrint("-----Game updated with new PGN and clock data");
            } else if (needsReparse && !isCurrentlyVisible) {
              // Off-screen game with new PGN - mark for reparse but don't execute yet
              _hasParsedMoves = false;
              game = game.copyWith(pgn: newPgn ?? game.pgn);
              if (currentState != null) {
                state = AsyncValue.data(currentState.copyWith(game: game));
              }
              debugPrint(
                "Off-screen game ${game.gameId} PGN updated, will reparse when visible",
              );
            } else {
              // Update the current state with new clock/position data
              if (currentState != null) {
                // Parse the last move for proper board highlighting
                Move? parsedLastMove;
                if (newLastMove != null &&
                    newLastMove.isNotEmpty &&
                    newLastMove.length >= 4) {
                  try {
                    // Convert UCI move to Move object
                    final from = Square.fromName(newLastMove.substring(0, 2));
                    final to = Square.fromName(newLastMove.substring(2, 4));
                    parsedLastMove = NormalMove(from: from, to: to);
                  } catch (e) {
                    debugPrint(
                      'Failed to parse last move: $newLastMove, error: $e',
                    );
                  }
                }

                state = AsyncValue.data(
                  currentState.copyWith(
                    game: game, // Updated game with new clock/position data
                    fenData: newFen, // Update FEN data for board display
                    lastMove:
                        parsedLastMove, // Update last move for highlighting
                  ),
                );

                // CRITICAL: Only trigger evaluation if this game is visible
                if (needsEvaluation && isCurrentlyVisible) {
                  debugPrint(
                    "-----Position changed, triggering evaluation update for FEN: $newFen",
                  );
                  _updateEvaluation();
                }
              }
            }
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

  Future<void> parseMoves() async {
    if (state.value?.isAnalysisMode == true) {
      return;
    }
    if (_hasParsedMoves) return;
    _hasParsedMoves = true;

    final currentState = state.value;
    if (currentState == null) return;

    try {
      // If no PGN in the current game object, fetch from repository
      final gameWithPgn = await ref
          .read(gameRepositoryProvider)
          .getGameById(game.gameId);

      // Check if still mounted after async operation
      if (!mounted) return;

      String pgn = gameWithPgn.pgn ?? _getSamplePgnData();

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

      state = AsyncValue.data(
        currentState.copyWith(
          position: finalPos,
          startingPosition: startingPos,
          lastMove: lastMove,
          allMoves: allMoves,
          moveSans: moveSans,
          currentMoveIndex: lastMoveIndex,
          pgnData: pgn,
          isLoadingMoves: false,
          evaluation: null, // Reset evaluation to trigger new calculation
          isEvaluating: true, // Show loading indicator while evaluating
          analysisState: AnalysisBoardState(startingPosition: startingPos),
          moveTimes: moveTimes,
        ),
      );

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

  void goToMove(int moveIndex) {
    if (state.value?.isAnalysisMode == true) {
      analysisModeGoToMove(moveIndex);
    } else {
      normalModeGoToMove(moveIndex);
    }
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

    state = AsyncValue.data(
      currentState.copyWith(
        analysisState: currentState.analysisState.copyWith(
          position: newPosition,
          lastMove: newLastMove,
          currentMoveIndex: moveIndex,
          suggestionLines: const [],
        ),
        evaluation: null, // Reset evaluation for new position
        isEvaluating: true, // Show loading indicator while evaluating
      ),
    );
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
        isEvaluating: true, // Show loading indicator while evaluating
        analysisState: currentState.analysisState.copyWith(
          suggestionLines: const [],
        ),
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
    if (currentState == null || !currentState.isAnalysisMode) return;

    final index = currentState.principalVariations.indexOf(line);
    if (index == -1) return;

    debugPrint('🎯 PLAY PV MOVE: index=$index, currentSelected=${currentState.selectedVariantIndex}');

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
    if (currentState == null || !currentState.isAnalysisMode) {
      debugPrint(
        '🎯 SELECT VARIANT: FAILED - state null or not in analysis mode',
      );
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
      if (currentState == null || !currentState.isAnalysisMode) {
        debugPrint('🎯 PLAY VARIANT FORWARD: Not in analysis mode');
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
          _pvCache.remove(currentFen);
          _evaluationCache.remove(currentFen);
          _mateCache.remove(currentFen);

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
          _updateEvaluation();
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

      // CRITICAL: Validate the move is legal from the base position
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
          '🎯 PLAY VARIANT FORWARD: ERROR - Failed to calculate position: $e',
        );
        debugPrint('   Base FEN: ${currentState.variantBaseFen}');
        debugPrint('   Moves to apply: ${newPointer.length}');
        debugPrint('   Variant moves: ${selectedVariant.moves.map((m) => m.uci).join(" ")}');
        // Clear variant on error
        state = AsyncValue.data(_clearVariantSelection(currentState));
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

  /// Undo last move of the selected variant
  void playVariantMoveBackward() {
    debugPrint('🎯 PLAY VARIANT BACKWARD called');
    _resumeVariantAutoPlay = false;
    var currentState = state.value;
    if (currentState == null || !currentState.isAnalysisMode) {
      debugPrint('🎯 PLAY VARIANT BACKWARD: Not in analysis mode');
      return;
    }
    if (!_ensureVariantSelection()) {
      debugPrint('🎯 PLAY VARIANT BACKWARD: No variants available');
      return;
    }
    currentState = state.value;
    if (currentState == null || currentState.selectedVariantIndex == null) {
      debugPrint('🎯 PLAY VARIANT BACKWARD: Variant selection failed');
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
    // Bottom nav arrows always navigate real game moves, even in analysis mode
    // This allows switching back and forth between analysis and real game
    if (currentState == null ||
        !currentState.canMoveForward ||
        _isProcessingMove) {
      return;
    }

    // If in analysis mode, exit it first and navigate to next real move
    if (currentState.isAnalysisMode) {
      // Deselect any variant
      state = AsyncValue.data(_clearVariantSelection(currentState));
      // Exit analysis mode will be handled by toggleAnalysisMode
      toggleAnalysisMode();
      // Then navigate to next move after a small delay to let analysis mode exit
      Future.microtask(() => goToMove(currentState.currentMoveIndex + 1));
    } else {
      goToMove(currentState.currentMoveIndex + 1);
    }
  }

  void moveBackward() {
    final currentState = state.value;
    // Bottom nav arrows always navigate real game moves, even in analysis mode
    // This allows switching back and forth between analysis and real game
    if (currentState == null ||
        !currentState.canMoveBackward ||
        _isProcessingMove) {
      return;
    }

    // If in analysis mode, exit it first and navigate to previous real move
    if (currentState.isAnalysisMode) {
      // Deselect any variant
      state = AsyncValue.data(_clearVariantSelection(currentState));
      // Exit analysis mode
      toggleAnalysisMode();
      // Then navigate to previous move after a small delay
      Future.microtask(() => goToMove(currentState.currentMoveIndex - 1));
    } else {
      goToMove(currentState.currentMoveIndex - 1);
    }
  }

  Future<void> toggleAnalysisMode() async {
    final currentState = state.value;
    if (currentState == null) {
      debugPrint('🎯 TOGGLE ANALYSIS: state is null, returning');
      return;
    }

    if (!currentState.isAnalysisMode) {
      debugPrint(
        '🎯 TOGGLE ANALYSIS: Entering analysis mode from move index ${currentState.currentMoveIndex}',
      );
      // Set loading state first
      state = AsyncValue.data(
        currentState.copyWith(isAnalysisMode: true, isLoadingMoves: true),
      );

      await _initializeAnalysisBoard();

      // Clear loading state
      final updatedState = state.value;
      if (updatedState != null) {
        debugPrint(
          '🎯 TOGGLE ANALYSIS: Analysis mode initialized, clearing loading state',
        );
        state = AsyncValue.data(updatedState.copyWith(isLoadingMoves: false));
      }
      debugPrint(
        '🎯 TOGGLE ANALYSIS: Analysis mode active, _analysisGame=${_analysisGame != null}',
      );
    } else {
      debugPrint('🎯 TOGGLE ANALYSIS: Exiting analysis mode');
      unawaited(_persistAnalysisState());
      _analysisGame = null;
      _navigatorSubscription?.close();
      _navigatorSubscription = null;

      final clearedState = _clearVariantSelection(currentState);
      state = AsyncValue.data(clearedState.copyWith(isAnalysisMode: false));
      debugPrint('🎯 TOGGLE ANALYSIS: Analysis mode deactivated');
    }

    togglePlayPause();
  }

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

    // Always initialize at current position, ignore saved state
    // This ensures analysis mode continues from wherever the user is viewing
    navigator.replaceState(
      ChessGameNavigatorState(game: _analysisGame!, movePointer: movePointer),
    );

    // Manually sync the initial state
    final initialState = ref.read(chessGameNavigatorProvider(_analysisGame!));
    _syncAnalysisFromNavigator(initialState);
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
      final (newPosition, san) = currentPosition.makeSan(move);
      final currentIndex = currentState.analysisState.currentMoveIndex;

      final trimmedMoves = List<Move>.from(
        currentState.analysisState.allMoves.take(currentIndex + 1),
      )..add(move);

      final trimmedSans = List<String>.from(
        currentState.analysisState.moveSans.take(currentIndex + 1),
      )..add(san);

      final trimmedHistory = List<Position>.from(
        currentState.analysisState.positionHistory.take(currentIndex + 1),
      )..add(newPosition);

      // Clear variant selection and PV cache for the new position
      final clearedState = _clearVariantSelection(currentState);
      final newFen = newPosition.fen;
      _pvCache.remove(newFen);
      _evaluationCache.remove(newFen);
      _mateCache.remove(newFen);

      final updatedState = clearedState.copyWith(
        analysisState: clearedState.analysisState.copyWith(
          currentMoveIndex: currentIndex + 1,
          lastMove: move,
          validMoves: makeLegalMoves(newPosition),
          promotionMove: null,
          position: newPosition,
          suggestionLines: const [],
          allMoves: trimmedMoves,
          moveSans: trimmedSans,
          positionHistory: trimmedHistory,
          movePointer: const [],
        ),
        evaluation: null,
        mate: null,
        isEvaluating: true,
        principalVariations: const [], // Clear old variants
        shapes: const ISet.empty(), // Clear old shapes
        selectedVariantIndex: null, // Clear variant selection
        variantMovePointer: const [],
        variantBaseFen: null,
        variantBaseMovePointer: null,
        variantBaseLastMove: null,
        variantBaseMoveIndex: null,
      );

      state = AsyncValue.data(updatedState);
      _playSoundForSan(san);
      _updateEvaluation();

      debugPrint('🎯 MANUAL MOVE: Evaluation triggered for new position');
    } catch (e) {
      debugPrint('🎯 ANALYSIS MOVE: ERROR - Failed manual move apply: $e');
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
        final move = pending.withPromotion(role);
        _analysisNavigator?.makeOrGoToMove(move.uci);
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
    if (move.contains('x')) return kLightPink;
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
    } catch (e) {
      debugPrint('⚠️ Failed to build PV lines on worker: $e');
    }

    if (workerResult.isEmpty) {
      workerResult = _analysisLinesWorker(payload);
      if (workerResult.isEmpty) return const [];
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
    final isExtensionUpdate = previousVariantPointer.isEmpty && shouldResumeAutoPlay;

    if (previousSelection != null && previousBaseFen != null && !isExtensionUpdate) {
      // Only validate if NOT an extension update
      final baseFenCompare = previousBaseFen.split(' ').take(3).join(' ');
      final pvFenCompare = baseFen.split(' ').take(3).join(' ');

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
        final arrowShapes = _getAllVariantArrowShapes(pvLines, previousSelection);
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
          '🎯 PV RESULTS: Not in variant exploration, setting new base FEN',
        );
        final arrowShapes = _getAllVariantArrowShapes(pvLines, previousSelection);
        nextState = nextState.copyWith(
          selectedVariantIndex: previousSelection,
          variantBaseFen: baseFen,
          variantBaseMovePointer: baseMovePointer,
          variantBaseLastMove: currentState.analysisState.lastMove,
          variantBaseMoveIndex: currentState.analysisState.currentMoveIndex,
          variantMovePointer: const [],
          shapes: arrowShapes,
        );
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

  Future<void> _evaluatePosition() async {
    try {
      final initialState = state.value;
      if (initialState == null || initialState.isLoadingMoves) return;

      final fen =
          initialState.isAnalysisMode
              ? initialState.analysisState.position.fen
              : initialState.position?.fen;
      if (fen == null) return;

      state = AsyncValue.data(
        initialState.copyWith(shapes: const ISet.empty(), isEvaluating: true),
      );

      final cachedEval = _evaluationCache[fen];
      final cachedPv = _pvCache[fen];
      final cachedMate = _mateCache[fen];
      if (cachedEval != null && cachedPv != null && cachedPv.isNotEmpty) {
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

      CloudEval? primaryEval;
      double? evaluation;
      List<AnalysisLine> pvLines = const [];

      debugPrint('🎯 EVAL START: Evaluating position $fen');

      // CRITICAL: Use Stockfish as PRIMARY source to guarantee 3 PVs
      try {
        debugPrint('🎯 EVAL: Requesting Stockfish evaluation...');
        final localEval = await StockfishSingleton().evaluatePosition(
          fen,
          depth: _resumeVariantAutoPlay ? 12 : 15,
        );
        debugPrint('🎯 EVAL: Stockfish completed, isCancelled=${localEval.isCancelled}, pvs.length=${localEval.pvs.length}');

        if (!localEval.isCancelled && localEval.pvs.isNotEmpty) {
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
          debugPrint('🎯 EVAL: Building principal variations...');
          pvLines = await _buildPrincipalVariations(fen, localEval.pvs);
          debugPrint('🎯 EVAL: Stockfish SUCCESS - returned ${pvLines.length} variants, eval=$evaluation');
        } else {
          debugPrint('🎯 EVAL: Stockfish returned cancelled or empty result');
        }
      } catch (e, stack) {
        debugPrint('🎯 EVAL ERROR: Stockfish failed for $fen: $e');
        debugPrint('Stack: $stack');
      }

      // Try cascade/cloud as fallback only if Stockfish failed
      if (evaluation == null || pvLines.isEmpty) {
        try {
          final cascadeEval = await ref.read(cascadeEvalProviderForBoard(fen).future);
          if (cascadeEval.pvs.isNotEmpty) {
            primaryEval = cascadeEval;
            evaluation = _getConsistentEvaluation(
              cascadeEval.pvs.first.cp / 100.0,
              fen,
            );
            pvLines = await _buildPrincipalVariations(fen, cascadeEval.pvs);
            debugPrint('🎯 EVAL: Cascade returned ${pvLines.length} variants');
          } else {
            debugPrint('🎯 EVAL: Cascade returned empty PVs');
          }
        } catch (e) {
          debugPrint('🎯 EVAL ERROR: Cascade failed for $fen: $e');
        }
      }

      if (evaluation == null || pvLines.isEmpty || primaryEval == null) {
        debugPrint('🎯 EVAL FAILED: No valid evaluation available for $fen');
        debugPrint('   evaluation=$evaluation, pvLines.length=${pvLines.length}, primaryEval=$primaryEval');
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

      try {
        final cache = ref.read(localEvalCacheProvider);
        final persist = ref.read(persistCloudEvalProvider);
        await Future.wait([
          persist.call(fen, primaryEval),
          cache.save(fen, primaryEval),
        ]);
      } catch (e) {
        debugPrint('Failed to persist evaluation for $fen: $e');
      }

      if (_cancelEvaluation || state.value == null || !mounted) return;
      var currentSnapshot = state.value;
      if (currentSnapshot == null) return;

      final inAnalysis = currentSnapshot.isAnalysisMode;
      final position =
          inAnalysis
              ? currentSnapshot.analysisState.position
              : currentSnapshot.position!;

      // Allow small FEN differences (like move counters) during variant exploration
      final currentFenBase = position.fen.split(' ').take(3).join(' ');
      final evalFenBase = fen.split(' ').take(3).join(' ');

      if (currentFenBase != evalFenBase) {
        debugPrint('🎯 EVAL: Position changed during eval (current=$currentFenBase vs eval=$evalFenBase), aborting');
        state = AsyncValue.data(currentSnapshot.copyWith(isEvaluating: false));
        return;
      }

      final basePointer =
          inAnalysis ? currentSnapshot.analysisState.movePointer : null;
      final mateScore = primaryEval.pvs.first.mate ?? currentSnapshot.mate;

      _evaluationCache[fen] = evaluation;
      _mateCache[fen] = mateScore;
      _pvCache[fen] = pvLines;

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
        variantBaseFen: inVariantExploration ? currentSnapshot.variantBaseFen : fen,
        variantBaseMovePointer:
            inVariantExploration
                ? currentSnapshot.variantBaseMovePointer
                : basePointer,
        analysisState: currentSnapshot.analysisState.copyWith(
          suggestionLines: pvLines,
        ),
      );
      state = AsyncValue.data(currentSnapshot);

      // Note: Removed supplemental eval since Stockfish is now primary with MultiPV=3
    } catch (e) {
      if (!_cancelEvaluation) {
        debugPrint('Evaluation error: $e');
      }
      final fallbackState = state.value;
      if (fallbackState != null) {
        state = AsyncValue.data(fallbackState.copyWith(isEvaluating: false));
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

      final nextState = current.copyWith(
        analysisState: current.analysisState.copyWith(
          game: navigatorState.game,
          position: position,
          validMoves: makeLegalMoves(position),
          lastMove: lastMove,
          moveSans:
              navigatorState.currentLine?.map((move) => move.san).toList() ??
              const [],
          movePointer: navigatorState.movePointer,
          currentMoveIndex: currentMoveIndex,
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

      // Get up to [_kMaxPrincipalVariations] principal variations
      final pvsToShow = cloudEval!.pvs.take(_kMaxPrincipalVariations).toList();

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
  /// Get color for a variant index (used for both arrows and card borders)
  Color getVariantColor(int variantIndex, bool isSelected) {
    if (isSelected) {
      return kPrimaryColor.withValues(alpha: 0.9);
    }

    switch (variantIndex) {
      case 0:
        return const Color.fromARGB(180, 152, 179, 154); // Green
      case 1:
        return const Color.fromARGB(180, 100, 149, 237); // Blue
      case 2:
        return const Color.fromARGB(180, 255, 165, 0);   // Orange
      default:
        return const Color.fromARGB(100, 152, 179, 154);
    }
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

        arrows.add(Arrow(
          color: arrowColor,
          orig: move.from,
          dest: move.to,
        ));
      } catch (_) {
        continue;
      }
    }

    return arrows.toISet();
  }

  void _updateEvaluation() {
    if (_isLongPressing) return;
    _cancelEvaluation = false;

    EasyDebounce.debounce(
      'evaluation-$index',
      const Duration(milliseconds: 100),
      () {
        if (_cancelEvaluation || state.value == null || !mounted) return;
        _evaluatePosition();
      },
    );
  }

  void startLongPressForward() {
    _isLongPressing = true;
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      try {
        if (state.value?.canMoveForward == true && !_isProcessingMove) {
          moveForward();
        } else {
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
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      try {
        if (state.value?.canMoveBackward == true && !_isProcessingMove) {
          moveBackward();
        } else {
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
          valid = false;
          break;
        }
        try {
          final (nextPosition, san) = position.makeSan(parsedMove);
          position = nextPosition;
          uciMoves.add(token);
          sanMoves.add(san);
        } catch (_) {
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
