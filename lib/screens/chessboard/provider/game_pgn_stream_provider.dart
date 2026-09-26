import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/utils/owned_stream.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Comprehensive game updates stream for live data (FEN, PGN, clocks, status).
///
/// Focused board views may use a single-game stream. Multi-game broadcast
/// surfaces must use [gameUpdatesBatchStreamProvider] so they do not exceed
/// Supabase's channel limits.
final gameUpdatesStreamProvider = AutoDisposeStreamProvider.family<
  Map<String, dynamic>?,
  String
>((ref, gameId) {
  // Board pages are built and disposed while swiping; see [ownedStream].
  return ownedStream(
    ref,
    ref.read(gameStreamRepositoryProvider).subscribeToGameUpdates(gameId),
  );
});

final liveGameUpdateStreamProvider =
    AutoDisposeStreamProvider.family<LiveGameUpdate?, String>((ref, gameId) {
      return ownedStream(
        ref,
        ref.read(gameStreamRepositoryProvider).subscribeToLiveGameUpdate(gameId),
      );
    });

@immutable
class LiveGamesBatchKey {
  LiveGamesBatchKey({
    required this.scopeId,
    required Iterable<String> gameIds,
    this.roundId,
    this.tourId,
  }) : gameIds = List.unmodifiable(
         gameIds.where((id) => id.isNotEmpty).toSet().toList()..sort(),
       );

  final String scopeId;
  final List<String> gameIds;
  final String? roundId;
  final String? tourId;

  bool get isScopedFilter =>
      (roundId != null && roundId!.isNotEmpty) ||
      (tourId != null && tourId!.isNotEmpty);

  bool contains(String gameId) {
    return gameIds.contains(gameId) || (isScopedFilter && gameId.isNotEmpty);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LiveGamesBatchKey) return false;
    if (other.scopeId != scopeId ||
        other.roundId != roundId ||
        other.tourId != tourId ||
        other.gameIds.length != gameIds.length) {
      return false;
    }
    for (var i = 0; i < gameIds.length; i++) {
      if (gameIds[i] != other.gameIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(scopeId, roundId, tourId, Object.hashAll(gameIds));
}

final gameUpdatesBatchStreamProvider = AutoDisposeStreamProvider.family<
  Map<String, LiveGameUpdate>,
  LiveGamesBatchKey
>((ref, key) {
  final repository = ref.read(gameStreamRepositoryProvider);
  final roundId = key.roundId?.trim();
  final tourId = key.tourId?.trim();
  final Stream<Map<String, LiveGameUpdate>> source;
  if (roundId != null && roundId.isNotEmpty) {
    source = repository.subscribeToLiveGameUpdatesForRound(roundId);
  } else if (tourId != null && tourId.isNotEmpty) {
    source = repository.subscribeToLiveGameUpdatesForTour(tourId);
  } else {
    source = repository.subscribeToLiveGameUpdatesBatch(key.gameIds);
  }

  // Cards scroll out before a slow initial snapshot; see [ownedStream].
  return ownedStream(ref, source);
});
