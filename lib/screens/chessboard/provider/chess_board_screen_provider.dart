import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ChessboardView { tour, countryman }

final chessboardViewFromProvider = StateProvider<ChessboardView>((ref) {
  return ChessboardView.tour;
});

final chessBoardScreenProvider = AutoDisposeStateNotifierProvider.family<
  ChessBoardScreenNotifier,
  AsyncValue<ChessBoardState>,
  int
>((ref, index) {
  final view = ref.watch(chessboardViewFromProvider);
  var games =
      view == ChessboardView.tour
          ? ref.watch(gamesTourScreenProvider).value!.gamesTourModels
          : ref.watch(countrymanGamesTourScreenProvider).value!.gamesTourModels;

  if (games[index].gameStatus == GameStatus.ongoing) {
    final subscribedStream = ref.watch(
      gamePgnStreamProvider(games[index].gameId),
    );
    subscribedStream.when(
      data: (data) {
        if (data != null) {
          games[index] = games[index].copyWith(pgn: data);
        } else {
          print('No Data');
        }
      },
      error: (error, _) {
        print('Error Data');
      },
      loading: () {
        print('Loading Data');
      },
    );
  }

  return ChessBoardScreenNotifier(ref, game: games[index], index: index);
});

class ChessBoardScreenNotifier
    extends StateNotifier<AsyncValue<ChessBoardState>> {
  ChessBoardScreenNotifier(this.ref, {required this.game, required this.index})
    : super(AsyncValue.loading()) {
    _initializeState();
  }

  final Ref ref;

  GamesTourModel game;
  final int index;

  Timer? _longPressTimer;
  bool _isLongPressing = false;

  void _initializeState() async {
    print("Initializing game: ${game.gameId}\nPGN: ${game.pgn}");

    try {
      // Create initial loading state with basic board setup
      final initialController = ChessBoardController();
      initialController.loadGameFromFEN(chess.Chess.DEFAULT_POSITION);


      // Set initial state with loading moves flag
      state = AsyncValue.data(
        ChessBoardState(
          baseGame: chess.Chess(),
          chessBoardController: initialController,
          uciMoves: [],
          sanMoves: [],
          currentMoveIndex: 0,
          isPlaying: false,
          isBoardFlipped: false,
          evaluations: 0.0,
          isLoadingMoves: true, // Show loading skeleton
        ),
      );

      // Now load the actual game data
      await _loadGameData();
    } catch (e) {
      print('Error initializing chess board: $e');
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> _loadGameData() async {
    try {
      // Create base game from PGN
      final baseGame = chess.Chess();
      final uciMoves = <String>[];
      final sanMoves = <String>[];

      // Fetch fresh game data from database
      final gameWithPGn = await ref
          .read(gameRepositoryProvider)
          .getGameById(game.gameId);

      game = GamesTourModel.fromGame(gameWithPGn);

      // Process PGN if available
      if (game.pgn != null && game.pgn!.isNotEmpty) {
        try {
          baseGame.load_pgn(game.pgn!);

          // Extract moves from history
          final history = baseGame.getHistory({'verbose': true});
          for (var move in history) {
            final from = move['from'] ?? '';
            final to = move['to'] ?? '';
            final promotion = move['promotion'] ?? '';

            String uciMove = '$from$to';
            if (promotion.isNotEmpty) {
              uciMove += promotion.toLowerCase();
            }

            uciMoves.add(uciMove);
            sanMoves.add(move['san'] ?? '');
          }
        } catch (e) {
          print('Error loading PGN: $e');
        }
      }

      // Create controller and set to final position initially
      final controller = ChessBoardController();
      controller.loadGameFromFEN(baseGame.fen);

      // Start at the end of the game
      final initialMoveIndex = uciMoves.length;

      // Update state with loaded data and turn off loading
      state = AsyncValue.data(
        ChessBoardState(
          baseGame: baseGame,
          chessBoardController: controller,
          uciMoves: uciMoves,
          sanMoves: sanMoves,
          currentMoveIndex: initialMoveIndex,
          isPlaying: false,
          isBoardFlipped: false,
          evaluations: 0.0,
          isLoadingMoves: false, // Loading complete
        ),
      );

      // Start evaluation for the current position
      _updateEvaluation();
    } catch (e) {
      print('Error loading game data: $e');

      // Set error state but keep the basic board visible
      if (mounted) {
        final currentState = state.value;
        if (currentState != null) {
          state = AsyncValue.data(
            currentState.copyWith(
              isLoadingMoves: false,
              sanMoves: [], // Empty moves list
            ),
          );
        } else {
          state = AsyncValue.error(e, StackTrace.current);
        }
      }
    }
  }

  // Method to refresh game data (useful for pull-to-refresh)
  Future<void> refreshGameData() async {
    final currentState = state.value;
    if (currentState == null) return;

    // Set loading state
    state = AsyncValue.data(
      currentState.copyWith(isLoadingMoves: true),
    );

    // Reload game data
    await _loadGameData();
  }

  // Core navigation method - builds position from scratch
  void _navigateToMoveIndex(int targetMoveIndex) {
    final st = state.value!;

    // Don't navigate while loading
    if (st.isLoadingMoves) return;

    // Validate bounds
    if (targetMoveIndex < 0 || targetMoveIndex > st.totalMoves) return;
    if (targetMoveIndex == st.currentMoveIndex) return;

    // Build position by replaying moves from start
    final positionGame = chess.Chess();

    for (int i = 0; i < targetMoveIndex; i++) {
      try {
        positionGame.move(st.sanMoves[i]);
      } catch (e) {
        print('Error replaying move ${st.sanMoves[i]}: $e');
        return;
      }
    }

    // Create new controller with the position
    final newController = ChessBoardController();
    newController.loadGameFromFEN(positionGame.fen);

    state = AsyncValue.data(
      st.copyWith(
        currentMoveIndex: targetMoveIndex,
        chessBoardController: newController,
      ),
    );

    _updateEvaluation();
  }

  // Public navigation methods
  void moveForward() {
    final st = state.value!;
    if (!st.canMoveForward || st.isLoadingMoves) return;
    _navigateToMoveIndex(st.currentMoveIndex + 1);
  }

  void moveBackward() {
    final st = state.value!;
    if (!st.canMoveBackward || st.isLoadingMoves) return;
    _navigateToMoveIndex(st.currentMoveIndex - 1);
  }

  void navigateToMove(int sanMoveIndex) {
    final st = state.value!;
    if (st.isLoadingMoves) return;

    // Convert SAN move index to position index
    // sanMoveIndex 0 = first move, we want to be at position 1 (after first move)
    _navigateToMoveIndex(sanMoveIndex + 1);
  }

  void resetGame() {
    final st = state.value!;
    if (st.isLoadingMoves) return;

    pauseGame();
    _navigateToMoveIndex(0);
  }

  void jumpToEnd() {
    final st = state.value!;
    if (st.isLoadingMoves) return;

    pauseGame();
    _navigateToMoveIndex(st.totalMoves);
  }

  // Auto-play functionality
  void togglePlayPause() {
    final st = state.value!;
    if (st.isLoadingMoves) return;

    if (st.isPlaying) {
      pauseGame();
    } else {
      startAutoPlay();
    }
  }

  void startAutoPlay() {
    final st = state.value!;
    if (st.isAtEnd || st.isLoadingMoves)
      return; // Can't play from end or while loading

    final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentSt = state.value!;
      if (currentSt.canMoveForward && !currentSt.isLoadingMoves) {
        moveForward();
      } else {
        // Reached end or loading started, stop auto-play
        timer.cancel();
        state = AsyncValue.data(
          currentSt.copyWith(isPlaying: false, autoPlayTimer: null),
        );
      }
    });

    state = AsyncValue.data(
      st.copyWith(isPlaying: true, autoPlayTimer: timer),
    );
  }

  void pauseGame() {
    final st = state.value!;
    if (st.isPlaying) {
      st.autoPlayTimer?.cancel();
      state = AsyncValue.data(
        st.copyWith(isPlaying: false, autoPlayTimer: null),
      );
    }
  }

  // Long press navigation
  void startLongPressForward() {
    final st = state.value!;
    if (_isLongPressing || st.isLoadingMoves) return;
    _isLongPressing = true;

    moveForward();
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final currentSt = state.value!;
      if (currentSt.canMoveForward && !currentSt.isLoadingMoves) {
        moveForward();
      } else {
        stopLongPress();
      }
    });
  }

  void startLongPressBackward() {
    final st = state.value!;
    if (_isLongPressing || st.isLoadingMoves) return;
    _isLongPressing = true;

    moveBackward();
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final currentSt = state.value!;
      if (currentSt.canMoveBackward && !currentSt.isLoadingMoves) {
        moveBackward();
      } else {
        stopLongPress();
      }
    });
  }

  void stopLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _isLongPressing = false;
  }

  bool get isLongPressing => _isLongPressing;

  // Board orientation
  void flipBoard(int gameIndex) {
    final st = state.value!;
    state = AsyncValue.data(
      st.copyWith(isBoardFlipped: !st.isBoardFlipped),
    );
  }

  // Evaluation
  Future<void> _updateEvaluation() async {
    const debounceTag = 'eval-debounce';
    EasyDebounce.debounce(
      debounceTag,
      const Duration(milliseconds: 300),
      () async {
        try {
          final st = state.value!;
          if (st.isLoadingMoves) return; // Don't evaluate while loading

          final fen = st.currentPosition.fen;
          final ev = await StockfishSingleton().evaluatePosition(fen);

          if (mounted) {
            state = AsyncValue.data(st.copyWith(evaluations: ev));
          }
        } catch (e) {
          print('Evaluation error: $e');
        }
      },
    );
  }

  // Utility methods for UI
  double getWhiteRatio(double eval) {
    return (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
  }

  double getBlackRatio(double eval) => 1.0 - getWhiteRatio(eval);

  Color getMoveColor(String move, int moveIndex) {
    final st = state.value!;

    // During loading, show dimmed colors
    if (st.isLoadingMoves) {
      return kWhiteColor.withOpacity(0.3);
    }

    // Current move gets white color
    if (moveIndex == st.currentMoveIndex - 1) {
      return kWhiteColor;
    }

    // Capture moves get pink
    if (move.contains('x')) return kLightPink;

    // Past moves get white, future moves get dimmed
    if (moveIndex < st.currentMoveIndex - 1) {
      return kWhiteColor;
    }

    return kWhiteColor70;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    state.value?.dispose();
    super.dispose();
  }
}
