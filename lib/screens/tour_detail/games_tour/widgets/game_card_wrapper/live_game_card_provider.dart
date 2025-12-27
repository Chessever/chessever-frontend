import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Parameters for liveGameCardProvider.
typedef LiveGameCardParams = ({String gameId, GamesTourModel baseGame});

/// Provider that combines the base game model with real-time updates from the stream.
/// This is used by game cards to show live updates without entering the game screen.
final liveGameCardProvider =
    AutoDisposeProvider.family<GamesTourModel, LiveGameCardParams>((
  ref,
  params,
) {
  final (:gameId, :baseGame) = params;

  // For finished games, return the base game directly (no stream needed)
  if (baseGame.gameStatus.isFinished) {
    return baseGame;
  }

  // Keep subscription alive for ongoing games to prevent churn when scrolling
  ref.keepAlive();

  // Watch the game updates stream - SharedGameStreamManager handles batching
  final streamAsync = ref.watch(gameUpdatesStreamProvider(gameId));

  return streamAsync.when(
    data: (gameData) {
      if (gameData == null) return baseGame;

      // Parse game status from stream
      GameStatus parseGameStatus(String? status) {
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
            return baseGame.gameStatus;
        }
      }

      // Merge streamed data with base game
      return baseGame.copyWith(
        pgn: gameData['pgn'] as String? ?? baseGame.pgn,
        fen: gameData['fen'] as String? ?? baseGame.fen,
        lastMove: gameData['last_move'] as String? ?? baseGame.lastMove,
        lastMoveTime: gameData['last_move_time'] != null
            ? DateTime.tryParse(gameData['last_move_time'] as String)
            : baseGame.lastMoveTime,
        whiteClockSeconds: (gameData['last_clock_white'] as num?)?.round() ??
            baseGame.whiteClockSeconds,
        blackClockSeconds: (gameData['last_clock_black'] as num?)?.round() ??
            baseGame.blackClockSeconds,
        gameStatus: parseGameStatus(gameData['status'] as String?),
      );
    },
    loading: () => baseGame,
    error: (_, __) => baseGame,
  );
});
