import 'dart:async';
import 'package:chess/chess.dart' as chess;
import 'package:square_bishop/square_bishop.dart' as square_bishop;
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

    // Load PGN if available
    if (game.pgn != null && game.pgn!.isNotEmpty) {
      chessGame.load_pgn(game.pgn!);
    }

    final squaresState = square_bishop.buildSquaresState(fen: chessGame.fen);

    // Get move history
    final allMoves = <String>[];
    final sanMoves = <String>[];

    // Reset to start and collect moves
    final tempGame = chess.Chess();
    if (game.pgn != null && game.pgn!.isNotEmpty) {
      tempGame.load_pgn(game.pgn!);
      final history = tempGame.getHistory({'verbose': true});

      for (var move in history) {
        allMoves.add(move['lan'] ?? move['from'] + move['to']);
        sanMoves.add(move['san'] ?? '');
      }
    }

    final currentMoveIndex =
        (state.value != null &&
                state.value?.currentMoveIndex != allMoves.length)
            ? state.value!.currentMoveIndex
            : allMoves.length;

    state = AsyncValue.data(
      ChessBoardState(
        game: chessGame,
        squaresState: squaresState!,
        allMoves: allMoves,
        sanMoves: sanMoves,
        currentMoveIndex: currentMoveIndex,
        isPlaying: false,
        isBoardFlipped: false,
        evaluations: 0.0,
        lastUpdatedGameIndex: null,
        lastUpdateTime: null,
      ),
    );

    _updateEvaluation();
  }

  static String _cleanPgnData(String pgn) {
    return pgn.replaceAll(RegExp(r'^\[Variant.*\r?\n', multiLine: true), '');
  }

  // Long press navigation methods
  void startLongPressForward() {
    if (_isLongPressing) return;

    _isLongPressing = true;
    // First move immediately
    moveForward();

    // Then continue with timer
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
    // First move immediately
    moveBackward();

    // Then continue with timer
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
    state.value?.autoPlayTimer?.cancel();
    super.dispose();
  }

  void moveForward() {
    final st = state.value!;
    if (st.currentMoveIndex >= st.allMoves.length) return;

    final moveResult = st.game.move(st.allMoves[st.currentMoveIndex]);
    if (moveResult == null) return; // Invalid move

    final squaresState = square_bishop.buildSquaresState(fen: st.game.fen);

    state = AsyncValue.data(
      st.copyWith(
        currentMoveIndex: st.currentMoveIndex + 1,
        squaresState: squaresState,
      ),
    );
    _updateEvaluation();
  }

  void moveBackward() {
    final st = state.value!;
    if (st.game.history.isEmpty) return;

    st.game.undo();

    final squaresState = square_bishop.buildSquaresState(fen: st.game.fen);

    state = AsyncValue.data(
      st.copyWith(
        currentMoveIndex: st.currentMoveIndex - 1,
        squaresState: squaresState,
      ),
    );
    _updateEvaluation();
  }

  // Fix in ChessBoardScreenNotifier
  void navigateToMove(int targetMoveIndex) {
    final st = state.value!;
    final current = st.currentMoveIndex - 1;
    if (targetMoveIndex == current) return;

    if (st.isPlaying) pauseGame();

    // Reset to start position
    st.game.reset();

    // Replay to desired index
    for (var i = 0; i <= targetMoveIndex; i++) {
      if (i < st.allMoves.length) {
        final moveResult = st.game.move(st.allMoves[i]);
        if (moveResult == null) break; // Stop if invalid move
      }
    }

    final squaresState = square_bishop.buildSquaresState(fen: st.game.fen);

    state = AsyncValue.data(
      st.copyWith(
        currentMoveIndex: targetMoveIndex + 1,
        squaresState: squaresState,
      ),
    );

    _updateEvaluation();
  }

  // Alternative: More explicit fix
  void navigateToMoveFixed(int targetMoveIndex) {
    final st = state.value!;
    if (st.isPlaying) pauseGame();

    // Reset to start position
    st.game.reset();

    // Play moves up to and INCLUDING the target move
    for (var i = 0; i <= targetMoveIndex; i++) {
      if (i < st.allMoves.length) {
        final moveResult = st.game.move(st.allMoves[i]);
        if (moveResult == null) break; // Stop if invalid move
      }
    }

    // Update squares state with new position
    final squaresState = square_bishop.buildSquaresState(fen: st.game.fen);

    state = AsyncValue.data(
      st.copyWith(
        currentMoveIndex: targetMoveIndex + 1,
        squaresState: squaresState!,
      ),
    );

    _updateEvaluation();
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

  void resetGame() {
    state.value!.autoPlayTimer?.cancel();
    state.value!.game.reset();

    final newIsPlaying = false;
    final newCurrentMoveIndex = 0;
    final squaresState = square_bishop.buildSquaresState(
      fen: state.value!.game.fen,
    );

    state = AsyncValue.data(
      state.value!.copyWith(
        isPlaying: newIsPlaying,
        currentMoveIndex: newCurrentMoveIndex,
        autoPlayTimer: null,
        squaresState: squaresState,
      ),
    );
  }

  void flipBoard(int gameIndex) {
    final newIsBoardFlipped = !state.value!.isBoardFlipped;
    state = AsyncValue.data(
      state.value!.copyWith(isBoardFlipped: newIsBoardFlipped),
    );
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
