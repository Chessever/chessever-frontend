import 'dart:async';
import 'dart:ui';
import 'package:bishop/bishop.dart' as bishop;
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:stockfish/stockfish.dart';

final chessBoardScreenProvider = AutoDisposeStateNotifierProvider.family<
  ChessBoardScreenNotifier,
  ChessBoardState,
  List<GamesTourModel>
>((ref, games) {
  return ChessBoardScreenNotifier(games);
});

class ChessBoardScreenNotifier extends StateNotifier<ChessBoardState> {
  final Stockfish _stockfish = StockfishSingleton().stockfish;

  ChessBoardScreenNotifier(List<GamesTourModel> games)
    : super(_initializeState(games));

  static ChessBoardState _initializeState(List<GamesTourModel> games) {
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

    return ChessBoardState(
      games: bishopGames,
      allMoves: allMoves,
      sanMoves: sanMoves,

      currentMoveIndex: List.filled(games.length, 0),
      isPlaying: List.filled(games.length, false),
      isBoardFlipped: List.filled(games.length, false),
      evaluations: List.filled(games.length, 0.0),
    );
  }

  static String _cleanPgnData(String pgn) {
    return pgn.replaceAll(RegExp(r'^\[Variant.*\r?\n', multiLine: true), '');
  }

  void moveForward(int gameIndex) {
    if (state.currentMoveIndex[gameIndex] < state.allMoves[gameIndex].length) {
      state.games[gameIndex].makeMoveString(
        state.allMoves[gameIndex][state.currentMoveIndex[gameIndex]],
      );
      final newCurrentMoveIndex = [...state.currentMoveIndex];
      newCurrentMoveIndex[gameIndex]++;
      state = state.copyWith(currentMoveIndex: newCurrentMoveIndex);
      _updateEvaluation(gameIndex);
    }
  }

  void moveBackward(int gameIndex) {
    if (state.games[gameIndex].canUndo) {
      state.games[gameIndex].undo();
      final newCurrentMoveIndex = [...state.currentMoveIndex];
      newCurrentMoveIndex[gameIndex]--;
      state = state.copyWith(currentMoveIndex: newCurrentMoveIndex);
      _updateEvaluation(gameIndex);
    }
  }

  void togglePlayPause(int gameIndex) {
    final newIsPlaying = [...state.isPlaying];
    newIsPlaying[gameIndex] = !newIsPlaying[gameIndex];

    if (newIsPlaying[gameIndex]) {
      final timer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (state.currentMoveIndex[gameIndex] <
            state.allMoves[gameIndex].length) {
          moveForward(gameIndex);
        } else {
          final stopPlaying = [...state.isPlaying];
          stopPlaying[gameIndex] = false;
          state = state.copyWith(isPlaying: stopPlaying, autoPlayTimer: null);
          timer.cancel();
        }
      });
      state = state.copyWith(isPlaying: newIsPlaying, autoPlayTimer: timer);
    } else {
      state.autoPlayTimer?.cancel();
      state = state.copyWith(isPlaying: newIsPlaying, autoPlayTimer: null);
    }
  }

  void resetGame(int gameIndex) {
    state.autoPlayTimer?.cancel();
    while (state.games[gameIndex].canUndo) {
      state.games[gameIndex].undo();
    }
    final newIsPlaying = [...state.isPlaying];
    final newCurrentMoveIndex = [...state.currentMoveIndex];
    newIsPlaying[gameIndex] = false;
    newCurrentMoveIndex[gameIndex] = 0;
    state = state.copyWith(
      isPlaying: newIsPlaying,
      currentMoveIndex: newCurrentMoveIndex,
      autoPlayTimer: null,
    );
  }

  void flipBoard(int gameIndex) {
    final newIsBoardFlipped = [...state.isBoardFlipped];
    newIsBoardFlipped[gameIndex] = !newIsBoardFlipped[gameIndex];
    state = state.copyWith(isBoardFlipped: newIsBoardFlipped);
  }

  Future<void> _updateEvaluation(int gameIndex) async {
    final fen = state.games[gameIndex].fen;
    _stockfish.stdin = 'position fen $fen';
    _stockfish.stdin = 'go depth 16';

    await for (final line in _stockfish.stdout) {
      if (line.contains('score cp')) {
        final score = RegExp(r'score cp (-?\d+)').firstMatch(line)?.group(1);
        if (score != null) {
          final newEvaluations = [...state.evaluations];
          newEvaluations[gameIndex] = int.parse(score) / 100.0;
          state = state.copyWith(evaluations: newEvaluations);
          break;
        }
      } else if (line.contains('score mate')) {
        final mate = RegExp(r'score mate (-?\d+)').firstMatch(line)?.group(1);
        if (mate != null) {
          final newEvaluations = [...state.evaluations];
          newEvaluations[gameIndex] = int.parse(mate) > 0 ? 10.0 : -10.0;
          state = state.copyWith(evaluations: newEvaluations);
          break;
        }
      }
    }
  }

  double getWhiteRatio(double eval) {
    final normalized = (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
    return (normalized * 0.99).clamp(0.01, 0.99);
  }

  double getBlackRatio(double eval) => 0.99 - getWhiteRatio(eval);

  Color getMoveColor(String move, int moveIndex, int gameIndex) {
    if (moveIndex == state.currentMoveIndex[gameIndex] - 1) {
      return kgradientEndColors;
    }
    if (move.contains('x')) return kLightPink;
    if (moveIndex < state.currentMoveIndex[gameIndex] - 1) {
      return kBoardColorDefault;
    }
    return kgradientEndColors;
  }

  void pauseGame(int gameIndex) {
    if (gameIndex < state.isPlaying.length && state.isPlaying[gameIndex]) {
      state.autoPlayTimer?.cancel();
      final newIsPlaying = [...state.isPlaying];
      newIsPlaying[gameIndex] = false;
      state = state.copyWith(isPlaying: newIsPlaying, autoPlayTimer: null);
    }
  }

  @override
  void dispose() {
    state.autoPlayTimer?.cancel();
    _stockfish.dispose();
    super.dispose();
  }
}
