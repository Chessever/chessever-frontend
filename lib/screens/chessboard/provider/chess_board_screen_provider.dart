import 'dart:async';
import 'dart:ui';
import 'package:bishop/bishop.dart' as bishop;
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:stockfish/stockfish.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final chessBoardScreenProvider = AutoDisposeStateNotifierProvider.family<
    ChessBoardScreenNotifier,
    ChessBoardState,
    List<GamesTourModel>
>((ref, games) {
  return ChessBoardScreenNotifier(games);
});

class ChessBoardScreenNotifier extends StateNotifier<ChessBoardState> {
  RealtimeChannel? _currentSubscription;
  final Stockfish _stockfish = StockfishSingleton().stockfish;
  String? _currentlySubscribedGameId;
  int _updateCount = 0;

  ChessBoardScreenNotifier(List<GamesTourModel> games)
      : super(_initializeState(games)) {
    print('Initializing ChessBoardScreenNotifier with ${games.length} games');
    print("pgn data: ${games.map((g) => g.pgn).join('\n')}");
  }

  /// Subscribe to updates for a specific game
  void subscribeToGame(int gameIndex) {
    if (gameIndex < 0 || gameIndex >= state.games.length) {
      print('Invalid game index: $gameIndex');
      return;
    }

    final game = state.games[gameIndex];
    final gameId = _getGameId(gameIndex);

    if (gameId == null) {
      print('No game ID found for index $gameIndex');
      return;
    }

    // Don't resubscribe if already subscribed to this game
    if (_currentlySubscribedGameId == gameId) {
      print('Already subscribed to game $gameId');
      return;
    }

    // Unsubscribe from previous game
    _unsubscribeFromCurrentGame();

    print('Subscribing to game $gameId at index $gameIndex');

    _currentSubscription = Supabase.instance.client
        .channel('live-game-$gameId')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'games',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: gameId,
      ),
      callback: (payload) => _handleGameUpdate(payload, gameIndex),
    )
        .subscribe((status, [error]) {
      _handleSubscriptionStatus(status, error, gameId);
    });

    _currentlySubscribedGameId = gameId;

    // Update state to reflect subscription status
    state = state.copyWith(
      subscriptionStatus:  RealtimeSubscribeStatus.timedOut,
      isConnected: false,
      lastError: null,
    );
  }

  /// Unsubscribe from current game
  void _unsubscribeFromCurrentGame() {
    if (_currentSubscription != null) {
      print('Unsubscribing from game $_currentlySubscribedGameId');
      _currentSubscription!.unsubscribe();
      _currentSubscription = null;
      _currentlySubscribedGameId = null;
    }
  }

  /// Handle subscription status changes
  void _handleSubscriptionStatus(RealtimeSubscribeStatus status, Object? error, String gameId) {
    print('Subscription status for game $gameId: $status');

    if (error != null) {
      print('Subscription error for game $gameId: $error');
      state = state.copyWith(
        subscriptionStatus: RealtimeSubscribeStatus.channelError,
        isConnected: false,
        lastError: error.toString(),
      );
    } else {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          print('Successfully subscribed to game $gameId updates');
          state = state.copyWith(
            subscriptionStatus:  RealtimeSubscribeStatus.subscribed,
            isConnected: true,
            lastError: null,
          );
          break;
        case RealtimeSubscribeStatus.timedOut:
          print('Subscription timed out for game $gameId');
          state = state.copyWith(
            subscriptionStatus: RealtimeSubscribeStatus.timedOut,
            isConnected: false,
            lastError: 'Subscription timed out',
          );
          break;
        case RealtimeSubscribeStatus.closed:
          print('Subscription closed for game $gameId');
          state = state.copyWith(
            subscriptionStatus: RealtimeSubscribeStatus.closed,
            isConnected: false,
            lastError: null,
          );
          break;
        case RealtimeSubscribeStatus.channelError:
          print('Channel error for game $gameId');
          state = state.copyWith(
            subscriptionStatus: RealtimeSubscribeStatus.channelError,
            isConnected: false,
            lastError: 'Channel error',
          );
          break;
      }
    }
  }

  /// Handle game update from Supabase
  void _handleGameUpdate(PostgresChangePayload payload, int gameIndex) {
    print('Update #${++_updateCount}: Received update for game at index $gameIndex');
    print('Payload: ${payload.newRecord}');

    final newPgn = payload.newRecord['pgn']?.toString();
    final newStatus = payload.newRecord['status']?.toString();
    final newFen = payload.newRecord['fen']?.toString();

    if (newPgn == null) {
      print('No PGN data in update');
      return;
    }

    try {
      // Parse the new game state
      final newGame = bishop.Game.fromPgn(_cleanPgnData(newPgn));

      // Reset to starting position to rebuild move history
      while (newGame.canUndo) {
        newGame.undo();
      }

      // Update the game state
      final games = [...state.games];
      final allMoves = [...state.allMoves];
      final sanMoves = [...state.sanMoves];
      final currentMoveIndex = [...state.currentMoveIndex];

      games[gameIndex] = newGame;
      allMoves[gameIndex] = newGame.moveHistoryAlgebraic;
      sanMoves[gameIndex] = newGame.moveHistorySan;

      // If game is auto-playing, maintain current position
      // Otherwise, go to the latest move
      if (!state.isPlaying[gameIndex]) {
        currentMoveIndex[gameIndex] = allMoves[gameIndex].length;

        // Apply all moves to show current position
        for (int i = 0; i < allMoves[gameIndex].length; i++) {
          games[gameIndex].makeMoveString(allMoves[gameIndex][i]);
        }
      }

      state = state.copyWith(
        games: games,
        allMoves: allMoves,
        sanMoves: sanMoves,
        currentMoveIndex: currentMoveIndex,
        lastUpdatedGameIndex: gameIndex,
        lastUpdateTime: DateTime.now(),
      );

      // Update evaluation for the current position
      _updateEvaluation(gameIndex);

      print('Game updated successfully: ${allMoves[gameIndex].length} moves');
      print('Current move index: ${currentMoveIndex[gameIndex]}');

    } catch (e) {
      print('Error updating game: $e');
      state = state.copyWith(
        lastError: 'Failed to update game: $e',
      );
    }
  }

  /// Get game ID from the game at the specified index
  String? _getGameId(int gameIndex) {
    if (gameIndex >= 0 && gameIndex < state.games.length) {
      // You'll need to store the original GamesTourModel to get the ID
      // For now, we'll assume you have a way to get the game ID
      // This might need to be passed differently or stored in state
      return "game_${gameIndex}_id"; // Replace with actual game ID logic
    }
    return null;
  }

  static ChessBoardState _initializeState(List<GamesTourModel> games) {
    final bishopGames = List.generate(
      games.length,
          (index) => bishop.Game.fromPgn(_cleanPgnData(games[index].pgn ?? '')),
    );

    final allMoves = bishopGames.map((game) => game.moveHistoryAlgebraic).toList();
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
      subscriptionStatus: null,
      isConnected: false,
      lastError: null,
      lastUpdatedGameIndex: null,
      lastUpdateTime: null,
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
        if (state.currentMoveIndex[gameIndex] < state.allMoves[gameIndex].length) {
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
    _unsubscribeFromCurrentGame();
    _stockfish.dispose();
    super.dispose();
  }
}