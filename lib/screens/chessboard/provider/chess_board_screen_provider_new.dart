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
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
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
  final Map<String, double> _evaluationCache = {};
  final Map<String, int?> _mateCache = {};

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
  /// Option 1: Always from white's perspective (consistent colors)
  /// Option 2: From current player's perspective (intuitive for current player)
  /// BULLETPROOF evaluation perspective handler
  /// This method GUARANTEES that ALL evaluations are in WHITE'S PERSPECTIVE
  double _getConsistentEvaluation(double evaluation, String fen) {
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final isBlackToMove = sideToMove == 'b';

    // CRITICAL FIX: Stockfish returns evaluations from CURRENT PLAYER'S perspective
    // - When White to move: positive = good for White (already correct for eval bar)
    // - When Black to move: positive = good for Black (must flip to White's perspective)

    double whitesPerspectiveEval;
    if (isBlackToMove) {
      // Black to move: Stockfish evaluation is from Black's perspective, flip it
      whitesPerspectiveEval = -evaluation;
      print("🔍 EVAL CORRECTED: FEN=$fen, side=BLACK, inputEval=$evaluation, outputEval=$whitesPerspectiveEval (FLIPPED to white's perspective)");
    } else {
      // White to move: Stockfish evaluation is already from White's perspective
      whitesPerspectiveEval = evaluation;
      print("🔍 EVAL UNCHANGED: FEN=$fen, side=WHITE, eval=$whitesPerspectiveEval (already white's perspective)");
    }

    print("🔍   evalBar expects: positive=WHITE advantage, negative=BLACK advantage");
    return whitesPerspectiveEval;
  }

  void _setupPgnStreamListener() {
    // Only listen to game updates stream if the game is ongoing
    if (game.gameStatus == GameStatus.ongoing) {
      ref.listen(gameUpdatesStreamProvider(game.gameId), (previous, next) {
        next.whenData((gameData) {
          if (gameData != null) {
            bool needsReparse = false;
            bool needsEvaluation = false;

            // Check if PGN changed
            final newPgn = gameData['pgn'] as String?;
            if (newPgn != null && newPgn != game.pgn) {
              needsReparse = true;
            }

            // Check if position changed (FEN or last_move) for evaluation updates
            final newFen = gameData['fen'] as String? ?? game.fen;
            final newLastMove = gameData['last_move'] as String? ?? game.lastMove;
            if (newFen != game.fen || newLastMove != game.lastMove) {
              needsEvaluation = true;
            }

            // Create updated game model with all live data
            game = game.copyWith(
              pgn: newPgn ?? game.pgn,
              fen: newFen,
              lastMove: newLastMove,
              lastMoveTime: gameData['last_move_time'] != null
                  ? DateTime.tryParse(gameData['last_move_time'] as String)
                  : game.lastMoveTime,
              whiteClockSeconds: (gameData['last_clock_white'] as num?)?.round(),
              blackClockSeconds: (gameData['last_clock_black'] as num?)?.round(),
              gameStatus: _parseGameStatus(gameData['status'] as String? ?? '*'),
            );

            // Re-parse moves if PGN changed
            if (needsReparse) {
              _hasParsedMoves = false;
              parseMoves();
              print("-----Game updated with new PGN and clock data");
            } else {
              // Update the current state with new clock/position data
              final currentState = state.value;
              if (currentState != null) {
                // Parse the last move for proper board highlighting
                Move? parsedLastMove;
                if (newLastMove != null && newLastMove.isNotEmpty && newLastMove.length >= 4) {
                  try {
                    // Convert UCI move to Move object
                    final from = Square.fromName(newLastMove.substring(0, 2));
                    final to = Square.fromName(newLastMove.substring(2, 4));
                    parsedLastMove = NormalMove(from: from, to: to);
                  } catch (e) {
                    print('Failed to parse last move: $newLastMove, error: $e');
                  }
                }

                state = AsyncValue.data(
                  currentState.copyWith(
                    game: game, // Updated game with new clock/position data
                    fenData: newFen, // Update FEN data for board display
                    lastMove: parsedLastMove, // Update last move for highlighting
                  ),
                );

                // Trigger evaluation update if position changed
                if (needsEvaluation) {
                  print("-----Position changed, triggering evaluation update for FEN: $newFen");
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
        evaluation: null, // Reset evaluation for new position
        isEvaluating: true, // Show loading indicator while evaluating
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
      _updateEvaluation();
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
      _updateEvaluation();
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

  Future<void> _evaluatePosition() async {
    try {
      final currentState = state.value;
      if (currentState == null || currentState.isLoadingMoves) return;

      final fen =
          currentState.isAnalysisMode
              ? currentState.analysisState.position.fen
              : currentState.position?.fen;
      print("----------- _evaluatePosition for fen: $fen");

      // CRITICAL DEBUGGING: Log detailed state information
      if (currentState.isAnalysisMode) {
        final analysisState = currentState.analysisState;
        print("🔍 ANALYSIS MODE: moveIndex=${analysisState.currentMoveIndex}, historyLen=${analysisState.positionHistory.length}");
        print("🔍   lastMove=${analysisState.lastMove}, position.fen=$fen");
        print("🔍   moveSans=${analysisState.moveSans.length > 0 ? analysisState.moveSans.last : 'none'}");
      } else {
        print("🔍 NORMAL MODE: position.fen=$fen");
        print("🔍   lastMove=${currentState.position != null ? 'present' : 'null'}");
      }

      if (fen == null) return;

      CloudEval? cloudEval;
      double evaluation = 0.0;
      print("Evaluating started for position: $fen");
      // Set evaluating state to show loading
      state = AsyncValue.data(
        currentState.copyWith(
          shapes: const ISet.empty(),
          isEvaluating: true,
        ),
      );
      try {
        // Force invalidate to bypass any cached wrong evaluations
        ref.invalidate(cascadeEvalProviderForBoard(fen));
        // Also try to clear local cache for this specific FEN (if accessible)
        print("🔄 FORCING FRESH EVALUATION for $fen (invalidating cache)");
        cloudEval = await ref.read(cascadeEvalProviderForBoard(fen).future);
        if (cloudEval?.pvs.isNotEmpty ?? false) {
          evaluation = _getConsistentEvaluation(
            cloudEval!.pvs.first.cp / 100.0,
            fen,
          );
        }
        print("Getting eval from cascadeEval: $fen");
      } catch (e) {
        print('Cascade eval failed, using local stockfish: $e');
        CloudEval result;
        try {
          var evaluatePosRes = await StockfishSingleton().evaluatePosition(
            fen,
            depth: 15, // Reduced depth for faster evaluation
          );
          if (evaluatePosRes.isCancelled) {
            print('Evaluation was cancelled for ${fen}');
            // Reset isEvaluating flag on cancellation
            final currState = state.value;
            if (currState != null) {
              state = AsyncValue.data(
                currState.copyWith(isEvaluating: false),
              );
            }
            return;
          } else {
            print('Evaluation was successful for ${fen}');
          }
          result = CloudEval(
            fen: fen,
            knodes: evaluatePosRes.knodes,
            depth: evaluatePosRes.depth,
            pvs: evaluatePosRes.pvs,
          );
        } catch (ex) {
          print('Stockfish evaluation failed for ${fen} with error: $ex');
          // Reset isEvaluating flag on error
          final currState = state.value;
          if (currState != null) {
            state = AsyncValue.data(
              currState.copyWith(isEvaluating: false),
            );
          }
          return;
        }
        if (result.pvs.isNotEmpty) {
          final rawCp = result.pvs.first.cp;
          evaluation = _getConsistentEvaluation(
            rawCp / 100.0,
            fen,
          );
          final fenParts = fen.split(' ');
          final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
          print("🔴 EVAL SOURCE: STOCKFISH FALLBACK - fen=$fen, side=$sideToMove, rawCp=$rawCp, finalEval=$evaluation");
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
        final rawCp = cloudEval?.pvs.isNotEmpty == true ? cloudEval!.pvs.first.cp : 0;
        final evaluationSource = cloudEval != null ? "cloudEval" : "fallback";

        print("🚨 SETTING EVAL: fen=$fen");
        print("🚨   side=$sideToMove, rawCp=$rawCp, finalEval=$evaluation");
        print("🚨   source=$evaluationSource, shapes=${shapes.length}");
        print("🚨   evalBar expects: positive=white advantage, negative=black advantage");

        // CRITICAL DEBUGGING: Position vs Move confusion analysis
        if (currentState.isAnalysisMode && currentState.analysisState.moveSans.isNotEmpty) {
          final lastMoveIndex = currentState.analysisState.currentMoveIndex - 1;
          final lastMoveSan = lastMoveIndex >= 0 && lastMoveIndex < currentState.analysisState.moveSans.length
              ? currentState.analysisState.moveSans[lastMoveIndex]
              : 'none';
          final moveNumber = (lastMoveIndex / 2).floor() + 1;
          final isWhiteMove = lastMoveIndex % 2 == 0;

          print("🎯 MOVE CONTEXT: lastMove=$lastMoveSan (move#$moveNumber, ${isWhiteMove ? 'WHITE' : 'BLACK'} just moved)");
          print("🎯   After ${isWhiteMove ? 'WHITE' : 'BLACK'} move, position has side=$sideToMove to move");
          print("🎯   Evaluation should represent advantage for ${isWhiteMove ? 'WHITE' : 'BLACK'} (who just moved)");

          // Sanity check: after white moves, black should be to move
          if (isWhiteMove && sideToMove != 'b') {
            print("⚠️  WARNING: After WHITE move, expected BLACK to move but side=$sideToMove");
          }
          if (!isWhiteMove && sideToMove != 'w') {
            print("⚠️  WARNING: After BLACK move, expected WHITE to move but side=$sideToMove");
          }
        }

        state = AsyncValue.data(
          currState.copyWith(
            evaluation: evaluation,
            isEvaluating: false,
            shapes: shapes,
            mate: cloudEval?.pvs.first.mate ?? 0, // Default to 0 if no mate value
          ),
        );
      }
      else{
        print("------- Skipping setting evaluation for outdated fen: $fen");
      }
    } catch (e) {
      if (!_cancelEvaluation) {
        print('Evaluation error: $e');
      }
    }
  }

  ISet<Shape> getBestMoveShape(Position pos, CloudEval? cloudEval) {
    ISet<Shape> shapes = const ISet.empty();
    if (cloudEval?.pvs.isNotEmpty ?? false) {
      String bestMove =
          cloudEval!.pvs[0].moves
              .split(" ")[0]
              .toLowerCase(); // Normalize to lowercase

      if (bestMove.length < 4 || bestMove.length > 5) {
        print('Invalid best move UCI: $bestMove');
        return shapes; // Invalid UCI
      }

      try {
        if (bestMove.contains('@')) {
          // Drop move (e.g., "p@e4")
          if (bestMove.length != 4 || bestMove[1] != '@') return shapes;
          String toStr = bestMove.substring(2, 4);
          Square to = Square.fromName(toStr);
          shapes =
              {
                Arrow(
                  color: const Color.fromARGB(255, 152, 179, 154),
                  orig: to, // Same square as destination
                  dest: to,
                ),
              }.toISet();
        } else {
          // Normal move or promotion (e.g., "e2e4" or "e7e8q")
          String fromStr = bestMove.substring(0, 2);
          String toStr = bestMove.substring(2, 4);
          Square from = Square.fromName(fromStr);
          Square to = Square.fromName(toStr);
          shapes =
              {
                Arrow(
                  color: const Color.fromARGB(255, 152, 179, 154),
                  orig: from,
                  dest: to,
                ),
              }.toISet();
        }
      } catch (e) {
        // Parsing failed, return empty
        print('Error parsing best move UCI: $e');
        return const ISet.empty();
      }
    } else {
      print('No evaluation data available.');
    }
    return shapes;
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
          _evaluatePosition()
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
    _evaluationCache.clear();
    _mateCache.clear();
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

  // Try to get the rounds, but if the provider is disposed, use games directly
  List<GamesTourModel> arrangedGames;
  try {
    final roundsAsync = ref.read(gamesAppBarProvider);
    if (roundsAsync.hasValue && roundsAsync.value != null) {
      final rounds = roundsAsync.value!.gamesAppBarModels;
      final reversedRounds = rounds.reversed.toList();

      arrangedGames = <GamesTourModel>[];
      for (var a = 0; a < reversedRounds.length; a++) {
        for (var b = 0; b < games.length; b++) {
          if (games[b].roundId == reversedRounds[a].id) {
            arrangedGames.add(games[b]);
          }
        }
      }
    } else {
      // Fallback: use games in their original order
      arrangedGames = games;
    }
  } catch (e) {
    // If gamesAppBarProvider is disposed or fails, use games as is
    arrangedGames = games;
  }

  // Ensure index is valid
  if (index >= arrangedGames.length) {
    index = arrangedGames.length - 1;
  }
  if (index < 0) {
    index = 0;
  }

  return ChessBoardScreenNotifierNew(
    ref,
    game: arrangedGames[index],
    index: index,
  );
});
