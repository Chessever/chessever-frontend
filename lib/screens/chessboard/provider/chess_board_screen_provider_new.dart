import 'dart:async';
import 'package:async/async.dart';
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
import 'package:flutter/material.dart';
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
    _setupPgnStreamListener();
  }

  final Ref ref;
  GamesTourModel game;
  final int index;
  Timer? _longPressTimer;
  bool _hasParsedMoves = false;
  bool _isProcessingMove = false;
  bool _isLongPressing = false;
  CancelableOperation<void>? _evalOperation;
  bool _cancelEvaluation = false;

  void _initializeState() {
    state = AsyncValue.data(
      ChessBoardStateNew(
        game: game,
        pgnData: null,
        isLoadingMoves: true,
        fenData: game.fen,
      ),
    );
  }

  void _setupPgnStreamListener() {
    // Only listen to PGN stream if the game is ongoing
    if (game.gameStatus == GameStatus.ongoing) {
      ref.listen(gamePgnStreamProvider(game.gameId), (previous, next) {
        next.whenData((pgnData) {
          if (pgnData != null && pgnData != game.pgn) {
            // Update the game with new PGN data
            game = game.copyWith(pgn: pgnData);
            // Re-parse moves with new PGN data
            _hasParsedMoves = false;
            parseMoves();
          }
        });
      });
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
      // Use the current game's PGN if available, otherwise fetch from repository
      String pgn = game.pgn ?? '';

      // If no PGN in the current game object, fetch from repository
      if (pgn.isEmpty) {
        final gameWithPgn = await ref
            .read(gameRepositoryProvider)
            .getGameById(game.gameId);
        pgn = gameWithPgn.pgn ?? _getSamplePgnData();
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
          evaluation: currentState.evaluation,
          analysisState: AnalysisBoardState(startingPosition: startingPos),
          moveTimes: moveTimes,
        ),
      );

      _updateEvaluation();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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
          times.add(
            _formatDisplayTime('-:--:--'),
          ); // Default for moves without time
        }
      }
    } catch (e) {
      print('Error parsing PGN: $e');
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
    _evalOperation?.cancel();
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
        ),
      ),
    );
    _cancelEvaluation = false;
    //_updateEvaluation();
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

    _evalOperation?.cancel();
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
        evaluation: currentState.evaluation,
      ),
    );

    _cancelEvaluation = false;
    _updateEvaluation();
    _isProcessingMove = false;
  }

  void evaluateCurrentPosition() {
    _updateEvaluation();
  }

  void moveForward() {
    final currentState = state.value;
    if (currentState?.isAnalysisMode == true) {
      if (currentState == null ||
          !currentState.analysisState.canMoveForward ||
          _isProcessingMove) {
        return;
      }
      goToMove(currentState.analysisState.currentMoveIndex + 1);
    } else {
      if (currentState == null ||
          !currentState.canMoveForward ||
          _isProcessingMove) {
        return;
      }
      goToMove(currentState.currentMoveIndex + 1);
    }
  }

  void moveBackward() {
    final currentState = state.value;
    if (currentState?.isAnalysisMode == true) {
      if (currentState == null ||
          !currentState.analysisState.canMoveBackward ||
          _isProcessingMove) {
        return;
      }
      goToMove(currentState.analysisState.currentMoveIndex - 1);
    } else {
      if (currentState == null ||
          !currentState.canMoveBackward ||
          _isProcessingMove) {
        return;
      }
      goToMove(currentState.currentMoveIndex - 1);
    }
  }

  void toggleAnalysisMode() {
    if (state.value?.isAnalysisMode == false) {
      initializeAnalysisBoard();
    }
    togglePlayPause();
    final currentState = state.value;

    if (currentState == null) return;

    state = AsyncValue.data(
      currentState.copyWith(isAnalysisMode: !currentState.isAnalysisMode),
    );
  }

  void initializeAnalysisBoard() {
    final currentState = state.value;
    if (currentState == null || currentState.position == null) return;

    state = AsyncValue.data(
      currentState.copyWith(
        analysisState: AnalysisBoardState(
          position: currentState.position!,
          validMoves: makeLegalMoves(currentState.position!),
          promotionMove: null,
          lastMove: currentState.lastMove,
          currentMoveIndex: currentState.currentMoveIndex,
          allMoves: currentState.allMoves.sublist(
            0,
            currentState.currentMoveIndex + 1,
          ),
          moveSans: currentState.moveSans.sublist(
            0,
            currentState.currentMoveIndex + 1,
          ),
        ),
      ),
    );
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
    var currentState = state.value;
    if (currentState == null) return;
    Position pos =
        currentState.isAnalysisMode
            ? currentState.analysisState.position
            : currentState.position!;
    AnalysisBoardState analysisState = currentState.analysisState;
    if (isPromotionPawnMove(move)) {
      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            promotionMove: move,
          ),
        ),
      );
    } else if (pos.isLegal(move)) {
      var positionHistory = analysisState.positionHistory;
      var moveSans = analysisState.moveSans;
      var allMoves = analysisState.allMoves;
      if (analysisState.currentMoveIndex <
          analysisState.positionHistory.length - 1) {
        positionHistory = analysisState.positionHistory.sublist(
          0,
          analysisState.currentMoveIndex + 1,
        );
        moveSans = analysisState.moveSans.sublist(
          0,
          analysisState.currentMoveIndex,
        );
        allMoves = analysisState.allMoves.sublist(
          0,
          analysisState.currentMoveIndex + 1,
        );
      }

      final newPosition = pos.playUnchecked(move);
      final sanMove = pos.makeSan(move);

      pos = newPosition;

      // Add to history
      final newPositionHistory = List<Position>.from(positionHistory)..add(pos);
      final newMoveSans = List<String>.from(moveSans)..add(sanMove.$2);
      final newAllMoves = List<Move>.from(allMoves)..add(move);
      var currentMoveIndex = analysisState.currentMoveIndex + 1;
      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            currentMoveIndex: currentMoveIndex,
            lastMove: move,
            validMoves: makeLegalMoves(pos),
            promotionMove: null,
            position: pos,
            positionHistory: newPositionHistory,
            moveSans: newMoveSans,
            allMoves: newAllMoves,
          ),
        ),
      );
    }
  }

  void onAnalysisPromotionSelection(Role? role) {
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
    } else if (currentState.analysisState.promotionMove != null) {
      AnalysisBoardState analysisState = currentState.analysisState;

      final move = analysisState.promotionMove!.withPromotion(role);
      // Remove any future moves if we're in the middle of history
      var positionHistory = analysisState.positionHistory;
      var moveSans = analysisState.moveSans;
      var allMoves = analysisState.allMoves;
      if (analysisState.currentMoveIndex <
          analysisState.positionHistory.length - 1) {
        positionHistory = analysisState.positionHistory.sublist(
          0,
          analysisState.currentMoveIndex + 1,
        );
        moveSans = analysisState.moveSans.sublist(
          0,
          analysisState.currentMoveIndex,
        );
        allMoves = analysisState.allMoves.sublist(
          0,
          analysisState.currentMoveIndex + 1,
        );
      }
      Position pos =
          currentState.isAnalysisMode
              ? currentState.analysisState.position
              : currentState.position!;
      final newPosition = pos.playUnchecked(move);
      final sanMove = pos.makeSan(move);
      pos = newPosition;

      final newPositionHistory = List<Position>.from(positionHistory)..add(pos);
      final newMoveSans = List<String>.from(moveSans)..add(sanMove.$2);
      final newAllMoves = List<Move>.from(allMoves)..add(move);
      var currentMoveIndex = analysisState.currentMoveIndex + 1;
      state = AsyncValue.data(
        currentState.copyWith(
          analysisState: currentState.analysisState.copyWith(
            currentMoveIndex: currentMoveIndex,
            lastMove: move,
            validMoves: makeLegalMoves(pos),
            promotionMove: null,
            position: pos,
            positionHistory: newPositionHistory,
            moveSans: newMoveSans,
            allMoves: newAllMoves,
          ),
        ),
      );
    }
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
      return kWhiteColor.withOpacity(0.3);
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

  Future<void> _evaluatePosition(int targetMoveIndex) async {
    try {
      final currentState = state.value;
      if (currentState == null || currentState.isLoadingMoves) return;

      final fen =
          currentState.isAnalysisMode
              ? currentState.analysisState.position.fen
              : currentState.position?.fen;
      if (fen == null) return;

      CloudEval? cloudEval;
      double evaluation = 0.0;

      try {
        cloudEval = await ref.read(cascadeEvalProviderForBoard(fen).future);
        if (cloudEval?.pvs.isNotEmpty ?? false) {
          evaluation = cloudEval!.pvs.first.cp / 100.0;
        }
      } catch (e) {
        print('Cascade eval failed, using local stockfish: $e');
        final result = await StockfishSingleton().evaluatePosition(
          fen,
          depth: 15, // Reduced depth for faster evaluation
        );
        if (result.pvs.isNotEmpty) {
          evaluation = result.pvs.first.cp / 100.0;
          List<String> fenParts = fen.split(' ');
          final isBlackTurn = fenParts[1] == 'b';
          if (isBlackTurn) {
            evaluation = -evaluation;
          }
        }
        cloudEval = result;
        try {
          final local = ref.read(localEvalCacheProvider);
          final persist = ref.read(persistCloudEvalProvider);
          await Future.wait([
            persist.call(fen, cloudEval),
            local.save(fen, cloudEval),
          ]);
        } catch (cacheError) {
          print('Cache error: $cacheError');
        }
      }

      // Only update state if the evaluation corresponds to the current move index
      if (_cancelEvaluation || state.value == null || !mounted) return;
      final currentMoveIndex = state.value!.currentMoveIndex;
      if (targetMoveIndex != currentMoveIndex) {
        print('Skipping evaluation for outdated move index: $targetMoveIndex');
        return;
      }

      state = AsyncValue.data(currentState.copyWith(evaluation: evaluation));
    } catch (e) {
      if (!_cancelEvaluation) {
        print('Evaluation error: $e');
      }
    }
  }

  void _updateEvaluation() {
    if (_isLongPressing) return;
    _cancelEvaluation = false;
    _evalOperation?.cancel();

    EasyDebounce.debounce(
      'evaluation-$index',
      const Duration(milliseconds: 100),
      () {
        if (_cancelEvaluation || state.value == null || !mounted) return;
        _evalOperation = CancelableOperation.fromFuture(
          _evaluatePosition(state.value!.currentMoveIndex),
        );
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
    _evalOperation?.cancel();
    _evalOperation = null;
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
    super.dispose();
  }
}

final chessBoardScreenProviderNew = AutoDisposeStateNotifierProvider.family<
  ChessBoardScreenNotifierNew,
  AsyncValue<ChessBoardStateNew>,
  int
>((ref, index) {
  final view = ref.watch(chessboardViewFromProviderNew);
  final games =
      view == ChessboardView.tour
          ? ref.watch(gamesTourScreenProvider).value!.gamesTourModels
          : ref.watch(countrymanGamesTourScreenProvider).value!.gamesTourModels;

  return ChessBoardScreenNotifierNew(ref, game: games[index], index: index);
});
