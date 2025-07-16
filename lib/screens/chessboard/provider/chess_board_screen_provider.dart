import 'dart:async';
import 'dart:ui';
import 'package:bishop/bishop.dart' as bishop;
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:stockfish/stockfish.dart';

final chessBoardScreenProvider = AutoDisposeStateNotifierProvider.family<
  ChessBoardScreenNotifier,
  AsyncValue<ChessBoardState>,
  int
>((ref, index) {
  var games = ref.watch(gamesTourScreenProvider).value!.gamesTourModels;
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
  return ChessBoardScreenNotifier(index: index, games: games);
});

class ChessBoardScreenNotifier
    extends StateNotifier<AsyncValue<ChessBoardState>> {
  ChessBoardScreenNotifier({required this.games, required this.index})
    : super(AsyncValue.loading()) {
    _initializeState(index);
  }

  final Stockfish _stockfish = StockfishSingleton().engine;
  StreamSubscription? _stockSub;
  int _lastEvalGame = -1;
  final int index;
  final List<GamesTourModel> games;

  void _initializeState(index) {
    final bishopGames = List.generate(
      games.length,
      (index) => bishop.Game.fromPgn(_cleanPgnData(games[index].pgn ?? '')),
    );

    final allMoves =
        bishopGames.map((game) => game.moveHistoryAlgebraic).toList();
    final sanMoves = bishopGames.map((game) => game.moveHistorySan).toList();

    // Reset games to starting position
    for (int i = 0; i < bishopGames.length; i++) {
      while (bishopGames[i].canUndo) {
        bishopGames[i].undo();
      }
    }
    state = AsyncValue.data(
      ChessBoardState(
        games: bishopGames,
        allMoves: allMoves,
        sanMoves: sanMoves,
        currentMoveIndex: List.filled(games.length, 0),
        isPlaying: List.filled(games.length, false),
        isBoardFlipped: List.filled(games.length, false),
        evaluations: List.filled(games.length, 0.0),
        subscriptionStatus: null,
        isConnected: false,
        lastError: null,
        lastUpdatedGameIndex: null,
        lastUpdateTime: null,
      ),
    );
    _updateEvaluation(index);
  }

  static String _cleanPgnData(String pgn) {
    return pgn.replaceAll(RegExp(r'^\[Variant.*\r?\n', multiLine: true), '');
  }

  void moveForward(int gameIndex) {
    if (state.value!.currentMoveIndex[gameIndex] <
        state.value!.allMoves[gameIndex].length) {
      state.value!.games[gameIndex].makeMoveString(
        state.value!.allMoves[gameIndex][state
            .value!
            .currentMoveIndex[gameIndex]],
      );
      final newCurrentMoveIndex = [...state.value!.currentMoveIndex];
      newCurrentMoveIndex[gameIndex]++;
      state = AsyncValue.data(
        state.value!.copyWith(currentMoveIndex: newCurrentMoveIndex),
      );
      _updateEvaluation(gameIndex);
    }
  }

  void moveBackward(int gameIndex) {
    if (state.value!.games[gameIndex].canUndo) {
      state.value!.games[gameIndex].undo();
      final newCurrentMoveIndex = [...state.value!.currentMoveIndex];
      newCurrentMoveIndex[gameIndex]--;
      state = AsyncValue.data(
        state.value!.copyWith(currentMoveIndex: newCurrentMoveIndex),
      );
      _updateEvaluation(gameIndex);
    }
  }

  void togglePlayPause(int gameIndex) {
    final newIsPlaying = [...state.value!.isPlaying];
    newIsPlaying[gameIndex] = !newIsPlaying[gameIndex];

    if (newIsPlaying[gameIndex]) {
      final timer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (state.value!.currentMoveIndex[gameIndex] <
            state.value!.allMoves[gameIndex].length) {
          moveForward(gameIndex);
        } else {
          final stopPlaying = [...state.value!.isPlaying];
          stopPlaying[gameIndex] = false;
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

  void resetGame(int gameIndex) {
    state.value!.autoPlayTimer?.cancel();
    while (state.value!.games[gameIndex].canUndo) {
      state.value!.games[gameIndex].undo();
    }
    final newIsPlaying = [...state.value!.isPlaying];
    final newCurrentMoveIndex = [...state.value!.currentMoveIndex];
    newIsPlaying[gameIndex] = false;
    newCurrentMoveIndex[gameIndex] = 0;
    state = AsyncValue.data(
      state.value!.copyWith(
        isPlaying: newIsPlaying,
        currentMoveIndex: newCurrentMoveIndex,
        autoPlayTimer: null,
      ),
    );
  }

  void flipBoard(int gameIndex) {
    final newIsBoardFlipped = [...state.value!.isBoardFlipped];
    newIsBoardFlipped[gameIndex] = !newIsBoardFlipped[gameIndex];
    state = AsyncValue.data(
      state.value!.copyWith(isBoardFlipped: newIsBoardFlipped),
    );
  }

  // replace _updateEvaluation with this tiny version:
  Future<void> _updateEvaluation(int gameIndex) async {
    await _stockSub?.cancel(); // cancel previous
    _lastEvalGame = gameIndex;

    final fen = state.value!.games[gameIndex].fen;
    final sf = StockfishSingleton().engine;
    sf.stdin = 'position fen $fen';
    sf.stdin = 'go depth 12';

    _stockSub = sf.stdout.listen((line) {
      if (_lastEvalGame != gameIndex) return; // stale answer
      double ev = 0;
      final cp = RegExp(r'score cp (-?\d+)').firstMatch(line)?.group(1);
      if (cp != null) {
        ev = int.parse(cp) / 100.0;
      } else {
        final mate = RegExp(r'score mate (-?\d+)').firstMatch(line)?.group(1);
        if (mate != null) ev = int.parse(mate).sign * 10.0;
      }
      if (line.startsWith('bestmove')) return; // finished

      final list = [...state.value!.evaluations];
      list[gameIndex] = ev;
      state = AsyncValue.data(state.value!.copyWith(evaluations: list));
    });
  }

  @override
  void dispose() {
    _stockSub?.cancel();
    state.value?.autoPlayTimer?.cancel();
    super.dispose();
  }

  double getWhiteRatio(double eval) {
    final normalized = (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
    return (normalized * 0.99).clamp(0.01, 0.99);
  }

  double getBlackRatio(double eval) => 0.99 - getWhiteRatio(eval);

  Color getMoveColor(String move, int moveIndex, int gameIndex) {
    if (moveIndex == state.value!.currentMoveIndex[gameIndex] - 1) {
      return kgradientEndColors;
    }
    if (move.contains('x')) return kLightPink;
    if (moveIndex < state.value!.currentMoveIndex[gameIndex] - 1) {
      return kBoardColorDefault;
    }
    return kgradientEndColors;
  }

  void pauseGame(int gameIndex) {
    if (gameIndex < state.value!.isPlaying.length &&
        state.value!.isPlaying[gameIndex]) {
      state.value!.autoPlayTimer?.cancel();
      final newIsPlaying = [...state.value!.isPlaying];
      newIsPlaying[gameIndex] = false;
      state = AsyncValue.data(
        state.value!.copyWith(isPlaying: newIsPlaying, autoPlayTimer: null),
      );
    }
  }
}
