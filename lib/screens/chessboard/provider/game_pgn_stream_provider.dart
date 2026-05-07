import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stream provider for PGN updates of a specific game.
/// Auto-disposes when the widget is no longer in view.
final gamePgnStreamProvider = AutoDisposeStreamProvider.family<String?, String>(
  (ref, gameId) {
    return ref.read(gameStreamRepositoryProvider).subscribeToPgn(gameId);
  },
);

/// Comprehensive game updates stream for live data (FEN, PGN, clocks, status).
///
/// Each game gets its own individual Realtime channel.
/// Auto-disposes when the widget is scrolled out of view, which automatically
/// cleans up the Supabase Realtime subscription.
final gameUpdatesStreamProvider = AutoDisposeStreamProvider.family<
  Map<String, dynamic>?,
  String
>((ref, gameId) {
  return ref.read(gameStreamRepositoryProvider).subscribeToGameUpdates(gameId);
});

final liveGameUpdateStreamProvider =
    AutoDisposeStreamProvider.family<LiveGameUpdate?, String>((ref, gameId) {
      return ref
          .read(gameStreamRepositoryProvider)
          .subscribeToLiveGameUpdate(gameId);
    });

@immutable
class LiveGamesBatchKey {
  LiveGamesBatchKey({required this.scopeId, required Iterable<String> gameIds})
    : gameIds = List.unmodifiable(
        gameIds.where((id) => id.isNotEmpty).toSet().toList()..sort(),
      );

  final String scopeId;
  final List<String> gameIds;

  bool contains(String gameId) => gameIds.contains(gameId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LiveGamesBatchKey) return false;
    if (other.scopeId != scopeId || other.gameIds.length != gameIds.length) {
      return false;
    }
    for (var i = 0; i < gameIds.length; i++) {
      if (gameIds[i] != other.gameIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(scopeId, Object.hashAll(gameIds));
}

final gameUpdatesBatchStreamProvider = AutoDisposeStreamProvider.family<
  Map<String, LiveGameUpdate>,
  LiveGamesBatchKey
>((ref, key) {
  return ref
      .read(gameStreamRepositoryProvider)
      .subscribeToLiveGameUpdatesBatch(key.gameIds);
});
