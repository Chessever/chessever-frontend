import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:advanced_chess_board/chess_board_controller.dart';
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

  return ChessBoardScreenNotifier(game: games[index], index: index);
});

class ChessBoardScreenNotifier
    extends StateNotifier<AsyncValue<ChessBoardState>> {
  ChessBoardScreenNotifier({required this.game, required this.index})
    : super(AsyncValue.loading()) {
    _initializeState();
  }

  final GamesTourModel game;
  final int index;

  Timer? _longPressTimer;
  bool _isLongPressing = false;

  void _initializeState() {
    print("My Current PGN: \n ${game.gameId} \n ${game.pgn}");
    final chessGame = chess.Chess();
    final chessBoardController = ChessBoardController();

    // Load PGN if available
    if (game.pgn != null && game.pgn!.isNotEmpty) {
      chessGame.load_pgn(game.pgn!);
      chessBoardController.loadGameFromFEN(chessGame.fen);
    }

    // Get move history - FIXED: Use proper UCI format
    final allMoves = <String>[];
    final sanMoves = <String>[];

    if (game.pgn != null && game.pgn!.isNotEmpty) {
      final tempGame = chess.Chess();
      tempGame.load_pgn(game.pgn!);
      final history = tempGame.getHistory({'verbose': true});

      for (var move in history) {
        // Use UCI format for moves (e2e4 format)
        final from = move['from'] ?? '';
        final to = move['to'] ?? '';
        final promotion = move['promotion'] ?? '';

        String uciMove = '$from$to';
        if (promotion.isNotEmpty) {
          uciMove += promotion.toLowerCase();
        }

        allMoves.add(uciMove);
        sanMoves.add(move['san'] ?? '');
      }
    }

    final currentMoveIndex = allMoves.length;

    state = AsyncValue.data(
      ChessBoardState(
        game: chessGame,
        chessBoardController: chessBoardController,
        allMoves: allMoves,
        sanMoves: sanMoves,
        currentMoveIndex: currentMoveIndex,
        isPlaying: false,
        isBoardFlipped: false,
        evaluations: 0.0,
      ),
    );

    _updateEvaluation();
  }

  // Enhanced move methods with proper state management
  void moveForward() {
    final st = state.value!;
    if (st.currentMoveIndex >= st.allMoves.length) return;

    // Create new game instance to ensure state change detection
    final newGame = chess.Chess();
    newGame.load(st.game.fen);

    // Replay moves up to the next one
    for (int i = 0; i <= st.currentMoveIndex; i++) {
      if (i < st.allMoves.length) {
        newGame.move(st.allMoves[i]);
      }
    }

    // Update controller with new position
    st.chessBoardController.loadGameFromFEN(newGame.fen);

    state = AsyncValue.data(
      st.copyWith(
        game: newGame,
        currentMoveIndex: st.currentMoveIndex + 1,
      ),
    );
    _updateEvaluation();
  }

  void moveBackward() {
    final st = state.value!;
    if (st.currentMoveIndex <= 0) return;

    // Create new game instance
    final newGame = chess.Chess();
    newGame.load(st.game.fen);

    // Replay moves up to previous position
    for (int i = 0; i < st.currentMoveIndex - 1; i++) {
      if (i < st.allMoves.length) {
        newGame.move(st.allMoves[i]);
      }
    }

    // Update controller with new position
    st.chessBoardController.loadGameFromFEN(newGame.fen);

    state = AsyncValue.data(
      st.copyWith(
        game: newGame,
        currentMoveIndex: st.currentMoveIndex - 1,
      ),
    );
    _updateEvaluation();
  }

  void navigateToMove(int targetMoveIndex) {
    final st = state.value!;
    if (targetMoveIndex < 0 || targetMoveIndex >= st.allMoves.length) return;
    if (targetMoveIndex == st.currentMoveIndex - 1) return;

    if (st.isPlaying) pauseGame();

    // Create new game instance
    final newGame = chess.Chess();
    newGame.load(st.game.fen);

    // Replay moves up to target position
    for (int i = 0; i <= targetMoveIndex; i++) {
      if (i < st.allMoves.length) {
        newGame.move(st.allMoves[i]);
      }
    }

    // Update controller with new position
    st.chessBoardController.loadGameFromFEN(newGame.fen);

    state = AsyncValue.data(
      st.copyWith(
        game: newGame,
        currentMoveIndex: targetMoveIndex + 1,
      ),
    );
    _updateEvaluation();
  }

  void resetGame() {
    final st = state.value!;
    st.autoPlayTimer?.cancel();

    final newGame = chess.Chess();
    if (game.pgn != null && game.pgn!.isNotEmpty) {
      newGame.load_pgn(game.pgn!);
    }

    st.chessBoardController.loadGameFromFEN(newGame.fen);

    state = AsyncValue.data(
      st.copyWith(
        game: newGame,
        isPlaying: false,
        currentMoveIndex: 0,
        autoPlayTimer: null,
      ),
    );
  }

  // Long press navigation methods
  void startLongPressForward() {
    if (_isLongPressing) return;

    _isLongPressing = true;
    moveForward();

    _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (
      timer,
    ) {
      if (state.value!.currentMoveIndex >= state.value!.allMoves.length) {
        stopLongPress();
        return;
      }
      moveForward();
    });
  }

  void startLongPressBackward() {
    if (_isLongPressing) return;

    _isLongPressing = true;
    moveBackward();

    _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (
      timer,
    ) {
      if (state.value!.game.history.isEmpty) {
        stopLongPress();
        return;
      }
      moveBackward();
    });
  }

  void stopLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _isLongPressing = false;
  }

  bool get isLongPressing => _isLongPressing;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    state.value?.dispose();
    super.dispose();
  }

  void flipBoard(int gameIndex) {
    final newIsBoardFlipped = !state.value!.isBoardFlipped;
    state = AsyncValue.data(
      state.value!.copyWith(isBoardFlipped: newIsBoardFlipped),
    );
  }

  void togglePlayPause() {
    final newIsPlaying = !state.value!.isPlaying;

    if (newIsPlaying) {
      final timer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (state.value!.currentMoveIndex < state.value!.allMoves.length) {
          moveForward();
        } else {
          final stopPlaying = false;
          state = AsyncValue.data(
            state.value!.copyWith(isPlaying: stopPlaying, autoPlayTimer: null),
          );
          timer.cancel();
        }
      });
      state = AsyncValue.data(
        state.value!.copyWith(isPlaying: newIsPlaying, autoPlayTimer: timer),
      );
    } else {
      state.value!.autoPlayTimer?.cancel();
      state = AsyncValue.data(
        state.value!.copyWith(isPlaying: newIsPlaying, autoPlayTimer: null),
      );
    }
  }

  Future<void> _updateEvaluation() async {
    const debounceTag = 'eval-debounce';
    EasyDebounce.debounce(
      debounceTag,
      const Duration(milliseconds: 500),
      () async {
        try {
          final fen = state.value!.game.fen;
          final ev = await StockfishSingleton().evaluatePosition(fen);
          print('Evaluation : $ev');
          if (mounted) {
            state = AsyncValue.data(state.value!.copyWith(evaluations: ev));
          }
        } catch (_) {
          // Silently ignore
        }
      },
    );
  }

  double getWhiteRatio(double eval) {
    return (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
  }

  double getBlackRatio(double eval) => 1.0 - getWhiteRatio(eval);

  Color getMoveColor(String move, int moveIndex) {
    if (moveIndex == state.value!.currentMoveIndex - 1) {
      return kWhiteColor;
    }
    if (move.contains('x')) return kLightPink;
    if (moveIndex < state.value!.currentMoveIndex - 1) {
      return kWhiteColor;
    }
    return kWhiteColor70;
  }

  void pauseGame() {
    if (state.value!.isPlaying) {
      state.value!.autoPlayTimer?.cancel();
      state = AsyncValue.data(
        state.value!.copyWith(isPlaying: false, autoPlayTimer: null),
      );
    }
  }
}
