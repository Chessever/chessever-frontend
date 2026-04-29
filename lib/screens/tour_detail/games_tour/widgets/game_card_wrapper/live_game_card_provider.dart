import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stores the base game model for each game, keyed by gameId.
/// Non-auto-dispose so it persists across provider rebuilds.
final baseGameProvider = StateProvider.family<GamesTourModel?, String>(
  (ref, gameId) => null,
);

/// Provider that combines the base game model with real-time updates from the stream.
/// This is used by game cards to show live updates without entering the game screen.
///
/// Keyed by gameId only (not baseGame) so that polling-triggered rebuilds of the
/// parent widget don't recreate the provider and disrupt the Supabase stream.
///
/// Auto-disposes when the widget is scrolled out of view, which automatically
/// cleans up the Supabase Realtime subscription for this game.
final liveGameCardProvider = AutoDisposeProvider.family<
  GamesTourModel?,
  String
>((ref, gameId) {
  final baseGame = ref.watch(baseGameProvider(gameId));
  if (baseGame == null) return null;

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
      final mergedPgn = gameData['pgn'] as String? ?? baseGame.pgn;
      final mergedLastMove =
          gameData['last_move'] as String? ?? baseGame.lastMove;
      final mergedStatus = parseGameStatus(gameData['status'] as String?);
      final mergedFen = resolveFreshestGameFen(
        fen: gameData['fen'] as String? ?? baseGame.fen,
        pgn: mergedPgn,
        lastMove: mergedLastMove,
      );

      final mergedGame = baseGame.copyWith(
        pgn: mergedPgn,
        fen: mergedFen ?? baseGame.fen,
        lastMove: mergedLastMove,
        lastMoveTime:
            gameData['last_move_time'] != null
                ? DateTime.tryParse(gameData['last_move_time'] as String)
                : baseGame.lastMoveTime,
        whiteClockSeconds: normalizedWhiteClock ?? baseGame.whiteClockSeconds,
        blackClockSeconds: normalizedBlackClock ?? baseGame.blackClockSeconds,
        gameStatus: mergedStatus,
      );
      if (_hasLiveFieldChanges(baseGame, mergedGame)) {
        _storeLatestBaseGame(ref, gameId, mergedGame);
      }
      return mergedGame;
    },
    loading: () => baseGame,
    error: (_, __) => baseGame,
  );
});

/// Helper that sets the base game and watches the live provider in one call.
/// Returns the live game data, falling back to the base game if not yet available.
GamesTourModel watchLiveGame(WidgetRef ref, GamesTourModel game) {
  final current = ref.read(baseGameProvider(game.gameId));
  if (_shouldUseIncomingGame(current, game, allowEqualFreshnessUpdate: false)) {
    Future.microtask(() {
      if (!ref.context.mounted) return;
      try {
        ref.read(baseGameProvider(game.gameId).notifier).state = game;
      } on StateError {
        // The card can be disposed while navigation is in flight.
      }
    });
  }
  return ref.watch(liveGameCardProvider(game.gameId)) ?? game;
}

void _storeLatestBaseGame(Ref ref, String gameId, GamesTourModel game) {
  Future.microtask(() {
    try {
      final current = ref.read(baseGameProvider(gameId));
      if (_shouldUseIncomingGame(
        current,
        game,
        allowEqualFreshnessUpdate: true,
      )) {
        ref.read(baseGameProvider(gameId).notifier).state = game;
      }
    } on StateError {
      // Provider/card was disposed while a stream event was being delivered.
    }
  });
}

bool _shouldUseIncomingGame(
  GamesTourModel? current,
  GamesTourModel incoming, {
  required bool allowEqualFreshnessUpdate,
}) {
  if (current == null) return true;
  if (current == incoming) return false;

  final currentTime = current.lastMoveTime;
  final incomingTime = incoming.lastMoveTime;
  if (currentTime != null && incomingTime != null) {
    if (incomingTime.isBefore(currentTime)) return false;
    if (incomingTime.isAfter(currentTime)) return true;
  } else if (currentTime != null && incomingTime == null) {
    return false;
  } else if (currentTime == null && incomingTime != null) {
    return true;
  }

  final currentPly = _knownPly(current);
  final incomingPly = _knownPly(incoming);
  if (currentPly != null && incomingPly != null) {
    if (incomingPly < currentPly) return false;
    if (incomingPly > currentPly) return true;
  } else if (currentPly != null && incomingPly == null) {
    return false;
  } else if (currentPly == null && incomingPly != null) {
    return true;
  }

  if ((current.lastMove?.isNotEmpty ?? false) &&
      (incoming.lastMove == null || incoming.lastMove!.isEmpty)) {
    return false;
  }

  if (current.gameStatus == GameStatus.ongoing &&
      incoming.gameStatus != GameStatus.ongoing) {
    return true;
  }
  if (current.gameStatus != GameStatus.ongoing &&
      incoming.gameStatus == GameStatus.ongoing) {
    return false;
  }

  return allowEqualFreshnessUpdate;
}

bool _hasLiveFieldChanges(GamesTourModel current, GamesTourModel incoming) {
  return current.pgn != incoming.pgn ||
      current.fen != incoming.fen ||
      current.lastMove != incoming.lastMove ||
      current.lastMoveTime != incoming.lastMoveTime ||
      current.whiteClockSeconds != incoming.whiteClockSeconds ||
      current.blackClockSeconds != incoming.blackClockSeconds ||
      current.gameStatus != incoming.gameStatus;
}

int? _knownPly(GamesTourModel game) {
  final pgnPly = resolveFinalPositionFromPgn(game.pgn)?.moveCount;
  final fenPly = plyFromFen(game.fen);
  if (pgnPly == null) return fenPly;
  if (fenPly == null) return pgnPly;
  return pgnPly > fenPly ? pgnPly : fenPly;
}
