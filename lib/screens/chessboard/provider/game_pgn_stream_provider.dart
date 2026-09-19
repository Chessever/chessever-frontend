import 'dart:async';

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
/// Focused board views may use a single-game stream. Multi-game broadcast
/// surfaces must use [gameUpdatesBatchStreamProvider] so they do not exceed
/// Supabase's channel limits.
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

  // Riverpod 2 can keep a disposed StreamProvider subscribed until its first
  // event resolves `.future`. Own the upstream subscription explicitly so a
  // slow initial snapshot cannot leave off-screen Realtime channels running.
  final controller = StreamController<Map<String, LiveGameUpdate>>();
  final subscription = source.listen(
    controller.add,
    onError: controller.addError,
    onDone: controller.close,
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});
