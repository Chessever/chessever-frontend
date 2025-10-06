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
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  final Map<String, double> _evaluationCache = {};
  final Map<String, int?> _mateCache = {};
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

  void _setupPgnStreamListener() {
    // Only listen to game updates stream if the game is ongoing
    if (game.gameStatus == GameStatus.ongoing) {
      ref.listen(gameUpdatesStreamProvider(game.gameId), (previous, next) {
        next.whenData((gameData) {
          if (gameData != null) {
            final currentState = state.value;

            // CRITICAL: Check if this game board is currently visible
            // This prevents off-screen games from playing audio or resetting positions
            final currentVisibleIndex = ref.read(currentlyVisiblePageIndexProvider);
            final isCurrentlyVisible = currentVisibleIndex == index;

            debugPrint('===== GAME UPDATE: Game ${game.gameId} (index $index), visible: $isCurrentlyVisible, analysisMode: ${currentState?.isAnalysisMode} =====');

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
                currentState.currentMoveIndex < currentState.allMoves.length - 1) {
              // User is viewing a past position, only update game data
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

              state = AsyncValue.data(currentState.copyWith(game: game));
              debugPrint("Game data updated but preserving user's current position");
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
    final currentState = state.value;
    if (currentState == null) return;
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
    _analysisNavigator?.goToMovePointerUnchecked(pointer);
  }

  void playPrincipalVariationMove(AnalysisLine line) {
    if (!state.value!.isAnalysisMode) return;
    if (line.moves.isEmpty) return;

    // Play the first move of the selected principal variation
    final firstMove = line.moves.first;
    if (firstMove is NormalMove) {
      if (isPromotionPawnMove(firstMove)) {
        state = AsyncValue.data(
          state.value!.copyWith(
            analysisState: state.value!.analysisState.copyWith(
              promotionMove: firstMove,
            ),
          ),
        );
      } else {
        if (_analysisGame != null) {
          _analysisNavigator?.makeOrGoToMove(firstMove.uci);
        } else {
          onAnalysisMove(firstMove);
        }
      }
    }
  }

  /// Select a variant (engine suggestion) for navigation
  void selectVariant(int variantIndex) {
    final currentState = state.value;
    if (currentState == null || !currentState.isAnalysisMode) return;
    if (variantIndex < 0 || variantIndex >= currentState.principalVariations.length) return;
    if (_analysisGame == null || _analysisNavigator == null) return;

    // Principal variations are generated for the position where analysis mode was entered
    // So we need to reset the navigator back to that position before playing the variant
    // The position is stored in analysisState.basePosition (the position when we entered analysis mode)

    // First, go back to the root position (where we entered analysis mode)
    // This is the position at currentMoveIndex when we called toggleAnalysisMode
    final currentMoveIndex = currentState.currentMoveIndex;
    final rootPointer = currentMoveIndex < 0 ? const <int>[] : [currentMoveIndex];

    _analysisNavigator?.goToMovePointerUnchecked(rootPointer);

    // Update state to show variant as selected
    state = AsyncValue.data(
      currentState.copyWith(
        selectedVariantIndex: variantIndex,
        variantMovePointer: const [], // Reset variant progress
      ),
    );

    // Immediately play the first move of the selected variant to update the board
    final selectedVariant = currentState.principalVariations[variantIndex];
    if (selectedVariant.moves.isNotEmpty) {
      final firstMove = selectedVariant.moves.first;
      if (firstMove is NormalMove) {
        if (isPromotionPawnMove(firstMove)) {
          state = AsyncValue.data(
            state.value!.copyWith(
              analysisState: state.value!.analysisState.copyWith(
                promotionMove: firstMove,
              ),
            ),
          );
        } else {
          _analysisNavigator?.makeOrGoToMove(firstMove.uci);

          // Update variant move pointer to reflect first move played
          state = AsyncValue.data(
            state.value!.copyWith(variantMovePointer: [0]),
          );
        }
      }
    }
  }

  /// Play next move of the selected variant forward
  void playVariantMoveForward() {
    final currentState = state.value;
    if (currentState == null || !currentState.isAnalysisMode) return;
    if (currentState.selectedVariantIndex == null) return;

    final selectedVariant = currentState.principalVariations[currentState.selectedVariantIndex!];
    final currentPointerIndex = currentState.variantMovePointer.length;

    // Check if there are more moves to play in the variant
    if (currentPointerIndex >= selectedVariant.moves.length) return;

    final nextMove = selectedVariant.moves[currentPointerIndex];
    if (nextMove is NormalMove) {
      if (isPromotionPawnMove(nextMove)) {
        state = AsyncValue.data(
          currentState.copyWith(
            analysisState: currentState.analysisState.copyWith(
              promotionMove: nextMove,
            ),
          ),
        );
      } else {
        if (_analysisGame != null) {
          _analysisNavigator?.makeOrGoToMove(nextMove.uci);
        } else {
          onAnalysisMove(nextMove);
        }

        // Update variant move pointer
        final newPointer = List<int>.from(currentState.variantMovePointer)..add(currentPointerIndex);
        state = AsyncValue.data(
          currentState.copyWith(variantMovePointer: newPointer),
        );
      }
    }
  }

  /// Undo last move of the selected variant
  void playVariantMoveBackward() {
    final currentState = state.value;
    if (currentState == null || !currentState.isAnalysisMode) return;
    if (currentState.variantMovePointer.isEmpty) return;

    // Go back one move using analysis navigator
    _analysisNavigator?.goToPreviousMove();

    // Update variant move pointer
    final newPointer = List<int>.from(currentState.variantMovePointer)..removeLast();
    state = AsyncValue.data(
      currentState.copyWith(variantMovePointer: newPointer),
    );
  }

  void moveForward() {
    final currentState = state.value;
    // Bottom nav arrows always navigate real game moves, even in analysis mode
    // This allows switching back and forth between analysis and real game
    if (currentState == null || !currentState.canMoveForward || _isProcessingMove) {
      return;
    }

    // If in analysis mode, exit it first and navigate to next real move
    if (currentState.isAnalysisMode) {
      // Deselect any variant
      state = AsyncValue.data(
        currentState.copyWith(
          selectedVariantIndex: null,
          variantMovePointer: const [],
        ),
      );
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
    if (currentState == null || !currentState.canMoveBackward || _isProcessingMove) {
      return;
    }

    // If in analysis mode, exit it first and navigate to previous real move
    if (currentState.isAnalysisMode) {
      // Deselect any variant
      state = AsyncValue.data(
        currentState.copyWith(
          selectedVariantIndex: null,
          variantMovePointer: const [],
        ),
      );
      // Exit analysis mode
      toggleAnalysisMode();
      // Then navigate to previous move after a small delay
      Future.microtask(() => goToMove(currentState.currentMoveIndex - 1));
    } else {
      goToMove(currentState.currentMoveIndex - 1);
    }
  }

  void toggleAnalysisMode() {
    final currentState = state.value;
    if (currentState == null) return;

    if (!currentState.isAnalysisMode) {
      _initializeAnalysisBoard();
    } else {
      unawaited(_persistAnalysisState());
      _analysisGame = null;
      _navigatorSubscription?.close();
      _navigatorSubscription = null;
    }

    togglePlayPause();

    state = AsyncValue.data(
      currentState.copyWith(isAnalysisMode: !currentState.isAnalysisMode),
    );
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
    final movePointer = currentMoveIndex < 0
        ? const <int>[]
        : [currentMoveIndex];

    debugPrint('===== ANALYSIS MODE: Initializing at move index $currentMoveIndex, pointer: $movePointer =====');

    // Set up listener BEFORE replaceState to capture the state change
    _navigatorSubscription?.close();
    _navigatorSubscription = ref.listen<ChessGameNavigatorState>(
      chessGameNavigatorProvider(_analysisGame!),
      (previous, next) {
        debugPrint('===== ANALYSIS MODE: Navigator state changed, movePointer: ${next.movePointer} =====');
        _syncAnalysisFromNavigator(next);
      },
      fireImmediately: false, // Don't fire immediately - we'll sync manually after replaceState
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
    if (_analysisGame != null) {
      if (isPromotionPawnMove(move)) {
        state = AsyncValue.data(
          state.value!.copyWith(
            analysisState: state.value!.analysisState.copyWith(
              promotionMove: move,
            ),
          ),
        );
      } else {
        _analysisNavigator?.makeOrGoToMove(move.uci);
      }
      return;
    }

    // Fallback for legacy behaviour when analysis navigator hasn't initialised
    var currentState = state.value;
    if (currentState == null) return;
    final pos =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position!;

    if (pos.isLegal(move)) {
      final newPosition = pos.playUnchecked(move);

      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            currentMoveIndex: currentState.analysisState.currentMoveIndex + 1,
            lastMove: move,
            validMoves: makeLegalMoves(newPosition),
            promotionMove: null,
            position: newPosition,
            suggestionLines: const [],
          ),
        ),
      );
      _updateEvaluation();
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
    if (state.value?.isAnalysisMode != true) return;
    _analysisNavigator?.goToNextMove();
  }

  /// Navigate backward in analysis mode (through main line when no variant selected)
  void analysisStepBackward() {
    if (state.value?.isAnalysisMode != true) return;
    _analysisNavigator?.goToPreviousMove();
  }

  void jumpToStart() {
    if (state.value?.isAnalysisMode == true) {
      _analysisNavigator?.goToHead();
    } else {
      goToMove(-1);
    }
  }

  void jumpToEnd() {
    final currentState = state.value;
    if (currentState == null) return;
    if (currentState.isAnalysisMode) {
      _analysisNavigator?.goToTail();
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

  List<AnalysisLine> _buildPrincipalVariations(String fen, List<Pv> pvs) {
    if (pvs.isEmpty) {
      return const [];
    }

    try {
      final basePosition = Position.setupPosition(
        Rule.chess,
        Setup.parseFen(fen),
      );

      final lines = <AnalysisLine>[];

      for (final pv in pvs) {
        final moves = <Move>[];
        final sanMoves = <String>[];
        var position = basePosition;
        double? evaluation;
        int? mate;

        if (pv.isMate && pv.mate != null) {
          mate = pv.mate;
        } else {
          // PVs are already in White's perspective (normalized before this call)
          evaluation = pv.cp / 100.0;
        }

        for (final token in pv.moves.split(' ')) {
          if (token.isEmpty) continue;
          final parsedMove = Move.parse(token);
          if (parsedMove == null) {
            break;
          }

          try {
            final (nextPosition, san) = position.makeSan(parsedMove);
            moves.add(parsedMove);
            sanMoves.add(san);
            position = nextPosition;
          } catch (_) {
            break;
          }
        }

        if (moves.isNotEmpty) {
          lines.add(
            AnalysisLine(
              moves: moves,
              sanMoves: sanMoves,
              evaluation: evaluation,
              mate: mate,
            ),
          );
        }
      }

      return lines;
    } catch (_) {
      return const [];
    }
  }

  ChessGameNavigator? get _analysisNavigator =>
      _analysisGame == null
          ? null
          : ref.read(chessGameNavigatorProvider(_analysisGame!).notifier);

  Future<void> _evaluatePosition() async {
    try {
      final currentState = state.value;
      if (currentState == null || currentState.isLoadingMoves) return;

      final fen =
          currentState.isAnalysisMode
              ? currentState.analysisState.position.fen
              : currentState.position?.fen;
      debugPrint("----------- _evaluatePosition for fen: $fen");

      // CRITICAL DEBUGGING: Log detailed state information
      if (currentState.isAnalysisMode) {
        final analysisState = currentState.analysisState;
        debugPrint(
          "🔍 ANALYSIS MODE: moveIndex=${analysisState.currentMoveIndex}, historyLen=${analysisState.positionHistory.length}",
        );
        debugPrint(
          "🔍   lastMove=${analysisState.lastMove}, position.fen=$fen",
        );
        debugPrint(
          "🔍   moveSans=${analysisState.moveSans.isNotEmpty ? analysisState.moveSans.last : 'none'}",
        );
      } else {
        debugPrint("🔍 NORMAL MODE: position.fen=$fen");
        debugPrint(
          "🔍   lastMove=${currentState.position != null ? 'present' : 'null'}",
        );
      }

      if (fen == null) return;

      CloudEval? cloudEval;
      double evaluation = 0.0;
      List<AnalysisLine> pvLines = const [];
      debugPrint("Evaluating started for position: $fen");
      // Set evaluating state to show loading
      state = AsyncValue.data(
        currentState.copyWith(shapes: const ISet.empty(), isEvaluating: true),
      );
      try {
        // Force invalidate to bypass any cached wrong evaluations
        ref.invalidate(cascadeEvalProviderForBoard(fen));
        // Also try to clear local cache for this specific FEN (if accessible)
        debugPrint("🔄 FORCING FRESH EVALUATION for $fen (invalidating cache)");
        cloudEval = await ref.read(cascadeEvalProviderForBoard(fen).future);
        final fetchedEval = cloudEval;
        if (fetchedEval != null && fetchedEval.pvs.isNotEmpty) {
          // CloudEval already in White's perspective (Lichess adapter flips it)
          evaluation = fetchedEval.pvs.first.cp / 100.0;
          pvLines = _buildPrincipalVariations(fen, fetchedEval.pvs);
        }
        debugPrint("Getting eval from cascadeEval: $fen");
      } catch (e) {
        debugPrint('Cascade eval failed, using local stockfish: $e');
        CloudEval result;
        try {
          var evaluatePosRes = await StockfishSingleton().evaluatePosition(
            fen,
            depth: 15, // Reduced depth for faster evaluation
          );
          if (evaluatePosRes.isCancelled) {
            debugPrint('Evaluation was cancelled for $fen');
            // Reset isEvaluating flag on cancellation
            final currState = state.value;
            if (currState != null) {
              state = AsyncValue.data(currState.copyWith(isEvaluating: false));
            }
            return;
          } else {
            debugPrint('Evaluation was successful for $fen');
          }
          result = CloudEval(
            fen: fen,
            knodes: evaluatePosRes.knodes,
            depth: evaluatePosRes.depth,
            pvs: evaluatePosRes.pvs,
          );
        } catch (ex) {
          debugPrint('Stockfish evaluation failed for $fen with error: $ex');
          // Reset isEvaluating flag on error
          final currState = state.value;
          if (currState != null) {
            state = AsyncValue.data(currState.copyWith(isEvaluating: false));
          }
          return;
        }
        if (result.pvs.isNotEmpty) {
          final fenParts = fen.split(' ');
          final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
          final isBlackToMove = sideToMove == 'b';

          // Stockfish returns current-player perspective, convert to White's perspective
          final normalizedPvs = result.pvs.map((pv) {
            if (isBlackToMove) {
              // Flip to White's perspective
              return Pv(
                moves: pv.moves,
                cp: -pv.cp,
                isMate: pv.isMate,
                mate: pv.mate != null ? -pv.mate! : null,
              );
            }
            return pv;
          }).toList();

          final rawCp = result.pvs.first.cp;
          evaluation = normalizedPvs.first.cp / 100.0; // Already in White's perspective
          pvLines = _buildPrincipalVariations(fen, normalizedPvs);

          debugPrint(
            "🔴 EVAL SOURCE: STOCKFISH FALLBACK - fen=$fen, side=$sideToMove, rawCp=$rawCp, finalEval=$evaluation (${isBlackToMove ? 'FLIPPED' : 'UNCHANGED'})",
          );

          // Update result with normalized PVs before caching
          cloudEval = CloudEval(
            fen: result.fen,
            knodes: result.knodes,
            depth: result.depth,
            pvs: normalizedPvs, // Use normalized (White's perspective) PVs
          );
        } else {
          cloudEval = result;
        }
        try {
          final local = ref.read(localEvalCacheProvider);
          final persist = ref.read(persistCloudEvalProvider);
          await Future.wait([
            persist.call(fen, cloudEval),
            local.save(fen, cloudEval),
          ]);
        } catch (cacheError) {
          debugPrint('Cache error: $cacheError');
        }
      }
      // Only update state if the evaluation corresponds to the current move index
      if (_cancelEvaluation || state.value == null || !mounted) return;
      var currState = state.value;
      if (currState == null) return;
      Position pos =
          currState.isAnalysisMode
              ? currState.analysisState.position
              : currState.position!;
      var shapes = getBestMoveShape(pos, cloudEval);
      if ((currState.isAnalysisMode &&
              currState.analysisState.position.fen == fen) ||
          (!currState.isAnalysisMode && currentState.position?.fen == fen)) {
        // COMPREHENSIVE DEBUGGING - Track evaluation source and perspective
        final fenParts = fen.split(' ');
        final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
        final rawCp =
            cloudEval?.pvs.isNotEmpty == true ? cloudEval!.pvs.first.cp : 0;
        final evaluationSource = cloudEval != null ? "cloudEval" : "fallback";

        debugPrint("🚨 SETTING EVAL: fen=$fen");
        debugPrint(
          "🚨   side=$sideToMove, rawCp=$rawCp, finalEval=$evaluation",
        );
        debugPrint("🚨   source=$evaluationSource, shapes=${shapes.length}");
        debugPrint(
          "🚨   evalBar expects: positive=white advantage, negative=black advantage",
        );

        // CRITICAL DEBUGGING: Position vs Move confusion analysis
        if (currentState.isAnalysisMode &&
            currentState.analysisState.moveSans.isNotEmpty) {
          final lastMoveIndex = currentState.analysisState.currentMoveIndex - 1;
          final lastMoveSan =
              lastMoveIndex >= 0 &&
                      lastMoveIndex < currentState.analysisState.moveSans.length
                  ? currentState.analysisState.moveSans[lastMoveIndex]
                  : 'none';
          final moveNumber = (lastMoveIndex / 2).floor() + 1;
          final isWhiteMove = lastMoveIndex % 2 == 0;

          debugPrint(
            "🎯 MOVE CONTEXT: lastMove=$lastMoveSan (move#$moveNumber, ${isWhiteMove ? 'WHITE' : 'BLACK'} just moved)",
          );
          debugPrint(
            "🎯   After ${isWhiteMove ? 'WHITE' : 'BLACK'} move, position has side=$sideToMove to move",
          );
          debugPrint(
            "🎯   Evaluation should represent advantage for ${isWhiteMove ? 'WHITE' : 'BLACK'} (who just moved)",
          );

          // Sanity check: after white moves, black should be to move
          if (isWhiteMove && sideToMove != 'b') {
            debugPrint(
              "⚠️  WARNING: After WHITE move, expected BLACK to move but side=$sideToMove",
            );
          }
          if (!isWhiteMove && sideToMove != 'w') {
            debugPrint(
              "⚠️  WARNING: After BLACK move, expected WHITE to move but side=$sideToMove",
            );
          }
        }

        final mateScore =
            (cloudEval?.pvs.isNotEmpty ?? false)
                ? cloudEval!.pvs.first.mate
                : null;

        state = AsyncValue.data(
          currState.copyWith(
            evaluation: evaluation,
            isEvaluating: false,
            shapes: shapes,
            mate: mateScore ?? currState.mate,
            principalVariations: pvLines,
            analysisState: currState.analysisState.copyWith(
              suggestionLines: pvLines,
            ),
          ),
        );
      } else {
        debugPrint(
          "------- Skipping setting evaluation for outdated fen: $fen",
        );
      }
    } catch (e) {
      if (!_cancelEvaluation) {
        debugPrint('Evaluation error: $e');
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

      state = AsyncValue.data(
        current.copyWith(
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
        ),
      );

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

      // Get up to 2 principal variations
      final pvsToShow = cloudEval!.pvs.take(2).toList();

      for (int i = 0; i < pvsToShow.length; i++) {
        final pv = pvsToShow[i];
        String bestMove =
            pv.moves
                .split(" ")[0]
                .toLowerCase(); // Normalize to lowercase

        if (bestMove.length < 4 || bestMove.length > 5) {
          debugPrint('Invalid best move UCI: $bestMove');
          continue; // Skip invalid UCI
        }

        try {
          // Use different colors/opacity for first and second best moves
          // First move: brighter green, second move: more transparent
          final arrowColor = i == 0
              ? const Color.fromARGB(255, 152, 179, 154) // Primary suggestion
              : const Color.fromARGB(180, 152, 179, 154); // Secondary suggestion (more transparent)

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
            arrowShapes.add(
              Arrow(
                color: arrowColor,
                orig: from,
                dest: to,
              ),
            );
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

  /// REMOVED: _getConsistentEvaluation
  ///
  /// This method was causing DOUBLE-FLIP bug:
  /// - Lichess adapter already flips Black-to-move positions to White's perspective
  /// - Supabase stores evaluations in White's perspective
  /// - This method was flipping AGAIN, causing incorrect evaluations
  ///
  /// FIX: All evaluation sources now normalized at source:
  /// - Cascade provider (Lichess/Supabase): Already in White's perspective
  /// - Stockfish fallback: Normalized inline before use (see _evaluatePosition)

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

  const ChessBoardProviderParams({
    required this.game,
    required this.index,
  });

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
