import 'dart:async';
import 'dart:ui';

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:dartchess/dartchess.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ChessboardView { tour, countryman }

final chessboardViewFromProviderNew = StateProvider<ChessboardView>((ref) {
  return ChessboardView.tour;
});

class ChessBoardScreenNotifierNew
    extends StateNotifier<AsyncValue<ChessBoardStateNew>> {
  ChessBoardScreenNotifierNew(
    this.ref, {
    required this.game,
    required this.index,
  }) : super(const AsyncValue.loading()) {
    _initializeState();
  }

  final Ref ref;
  GamesTourModel game;
  final int index;
  Timer? _longPressTimer;
  bool _hasParsedMoves = false;

  void _initializeState() {
    state = AsyncValue.data(
      ChessBoardStateNew(
        game: game,
        pgnData: null,
        isLoadingMoves: true,
      ),
    );
  }

  Future<void> parseMoves() async {
    if (_hasParsedMoves) return;
    _hasParsedMoves = true;

    final currentState = state.value;
    if (currentState == null) return;

    try {
      final gameWithPGn = await ref
          .read(gameRepositoryProvider)
          .getGameById(game.gameId);
      final pgn = gameWithPGn.pgn ?? _getSamplePgnData();

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
        ),
      );

      _updateEvaluation();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // Navigation methods
  void goToMove(int moveIndex) {
    final currentState = state.value;
    if (currentState == null) return;
    if (currentState.isLoadingMoves) return;

    if (moveIndex < -1 || moveIndex >= currentState.allMoves.length) return;

    // Replay the game up to the current move
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
      ),
    );
    _updateEvaluation();
  }

  void evaluateCurrentPosition() {
    _updateEvaluation();
  }

  void moveForward() {
    final currentState = state.value;
    if (currentState == null || !currentState.canMoveForward) return;

    goToMove(currentState.currentMoveIndex + 1);
  }

  void moveBackward() {
    final currentState = state.value;
    if (currentState == null || !currentState.canMoveBackward) return;

    goToMove(currentState.currentMoveIndex - 1);
  }

  void jumpToStart() {
    goToMove(-1);
  }

  void jumpToEnd() {
    final currentState = state.value;
    if (currentState == null) return;

    goToMove(currentState.allMoves.length - 1);
  }

  void resetGame() {
    jumpToStart();
  }

  // Board control methods
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

  // Helper methods
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

  Future<void> _updateEvaluation() async {
    const debounceTag = 'eval-debounce';
    EasyDebounce.debounce(
      debounceTag,
      const Duration(milliseconds: 300),
      () async {
        try {
          final currentState = state.value;
          if (currentState == null || currentState.isLoadingMoves) return;

          final fen = currentState.position?.fen;
          if (fen == null) return;

          CloudEval? cloudEval;
          double evaluation = 0.0;

          try {
            // Try to get evaluation from cascade provider first
            cloudEval = await ref.read(cascadeEvalProviderForBoard(fen).future);

            // Extract evaluation from CloudEval
            if (cloudEval?.pvs.isNotEmpty ?? false) {
              evaluation =
                  cloudEval!.pvs.first.cp /
                  100.0; // Convert centipawns to pawns
            }
          } catch (e) {
            print('Cascade eval failed, using local stockfish: $e');

            // Fallback to local Stockfish
            final result = await StockfishSingleton().evaluatePosition(
              fen,
              depth: 17,
            );

            // Extract evaluation from CloudEval
            if (result.pvs.isNotEmpty) {
              evaluation =
                  result.pvs.first.cp / 100.0; // Convert centipawns to pawns

              // Adjust for black's turn
              List<String> fenParts = fen.split(' ');
              final isBlackTurn = fenParts[1] == 'b';
              if (isBlackTurn) {
                evaluation = -evaluation;
              }
            }

            // Create CloudEval for caching
            cloudEval = result;

            // Cache the result
            try {
              final local = ref.read(localEvalCacheProvider);
              final persist = ref.read(persistCloudEvalProvider);

              Future.wait<void>([
                persist.call(fen, cloudEval), // writes positions, evals, pvs
                local.save(fen, cloudEval), // local cache
              ]);
            } catch (cacheError) {
              print('Cache error: $cacheError');
            }
          }

          // Check if the state is still valid before updating
          if (state.value != null && mounted) {
            state = AsyncValue.data(
              currentState.copyWith(evaluation: evaluation),
            );
          }
        } catch (e) {
          print('Evaluation error: $e');
        }
      },
    );
  }

  void startLongPressForward() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        try {
          if (state.value?.canMoveForward == true) moveForward();
        } on StateError {
          _longPressTimer?.cancel();
          _longPressTimer = null;
        }
      },
    );
  }

  void startLongPressBackward() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) {
        try {
          if (state.value?.canMoveBackward == true) moveBackward();
        } on StateError {
          _longPressTimer?.cancel();
          _longPressTimer = null;
        }
      },
    );
  }

  double getWhiteRatio(double eval) {
    return (eval.clamp(-5.0, 5.0) + 5.0) / 10.0;
  }

  double getBlackRatio(double eval) => 1.0 - getWhiteRatio(eval);

  void stopLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  @override
  void dispose() {
    stopLongPress();
    super.dispose();
  }
}

// Updated provider
final chessBoardScreenProviderNew = AutoDisposeStateNotifierProvider.family<
  ChessBoardScreenNotifierNew,
  AsyncValue<ChessBoardStateNew>,
  int
>((ref, index) {
  final view = ref.watch(chessboardViewFromProviderNew);
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
        }
      },
      error: (error, _) {
        print('Error loading PGN stream: $error');
      },
      loading: () {
        print('Loading PGN stream...');
      },
    );
  }

  return ChessBoardScreenNotifierNew(ref, game: games[index], index: index);
});

// Convenience providers for easy access to specific state parts
final currentMoveIndexProvider = Provider.family<int, int>((ref, index) {
  return ref
      .watch(chessBoardScreenProviderNew(index))
      .maybeWhen(data: (state) => state.currentMoveIndex, orElse: () => -1);
});

final canMoveForwardProvider = Provider.family<bool, int>((ref, index) {
  return ref
      .watch(chessBoardScreenProviderNew(index))
      .maybeWhen(data: (state) => state.canMoveForward, orElse: () => false);
});

final canMoveBackwardProvider = Provider.family<bool, int>((ref, index) {
  return ref
      .watch(chessBoardScreenProviderNew(index))
      .maybeWhen(data: (state) => state.canMoveBackward, orElse: () => false);
});

final moveSansProvider = Provider.family<List<String>, int>((ref, index) {
  return ref
      .watch(chessBoardScreenProviderNew(index))
      .maybeWhen(data: (state) => state.moveSans, orElse: () => []);
});

final boardPositionProvider = Provider.family<Position?, int>((ref, index) {
  return ref
      .watch(chessBoardScreenProviderNew(index))
      .maybeWhen(data: (state) => state.position, orElse: () => null);
});
