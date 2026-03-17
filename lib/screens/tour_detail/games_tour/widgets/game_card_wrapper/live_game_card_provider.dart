import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stores the base game model for each game, keyed by gameId.
/// Non-auto-dispose so it persists across provider rebuilds.
final baseGameProvider =
    StateProvider.family<GamesTourModel?, String>((ref, gameId) => null);

/// Provider that combines the base game model with real-time updates from the stream.
/// This is used by game cards to show live updates without entering the game screen.
///
/// Keyed by gameId only (not baseGame) so that polling-triggered rebuilds of the
/// parent widget don't recreate the provider and disrupt the Supabase stream.
///
/// Auto-disposes when the widget is scrolled out of view, which automatically
/// cleans up the Supabase Realtime subscription for this game.
final liveGameCardProvider =
    AutoDisposeProvider.family<GamesTourModel?, String>((ref, gameId) {
  final baseGame = ref.read(baseGameProvider(gameId));
  if (baseGame == null) return null;

  // For finished games, return the base game directly (no stream needed)
  if (baseGame.gameStatus.isFinished) {
    return baseGame;
  }

  // NO ref.keepAlive() - allow auto-dispose when scrolled out of view
  // This ensures the Realtime channel is cleaned up properly

  // Watch the game updates stream - individual channel per game
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
      final streamedWhiteClock =
          (gameData['last_clock_white'] as num?)?.round();
      final streamedBlackClock =
          (gameData['last_clock_black'] as num?)?.round();
      final normalizedWhiteClock = GamesTourModel.normalizeClockSeconds(
        clockSeconds: streamedWhiteClock,
        clockCentiseconds: baseGame.whiteClockCentiseconds,
      );
      final normalizedBlackClock = GamesTourModel.normalizeClockSeconds(
        clockSeconds: streamedBlackClock,
        clockCentiseconds: baseGame.blackClockCentiseconds,
      );

      return baseGame.copyWith(
        pgn: gameData['pgn'] as String? ?? baseGame.pgn,
        fen: gameData['fen'] as String? ?? baseGame.fen,
        lastMove: gameData['last_move'] as String? ?? baseGame.lastMove,
        lastMoveTime:
            gameData['last_move_time'] != null
                ? DateTime.tryParse(gameData['last_move_time'] as String)
                : baseGame.lastMoveTime,
        whiteClockSeconds: normalizedWhiteClock ?? baseGame.whiteClockSeconds,
        blackClockSeconds: normalizedBlackClock ?? baseGame.blackClockSeconds,
        gameStatus: parseGameStatus(gameData['status'] as String?),
      );
    },
    loading: () => baseGame,
    error: (_, __) => baseGame,
  );
});

/// Helper that sets the base game and watches the live provider in one call.
/// Returns the live game data, falling back to the base game if not yet available.
GamesTourModel watchLiveGame(WidgetRef ref, GamesTourModel game) {
  ref.read(baseGameProvider(game.gameId).notifier).state = game;
  return ref.watch(liveGameCardProvider(game.gameId)) ?? game;
}
