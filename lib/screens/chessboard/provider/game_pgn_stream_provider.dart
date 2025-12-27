import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamePgnStreamProvider =
    AutoDisposeStreamProvider.family<String?, String>((
  ref,
  gameId,
) {
  return ref.read(gameStreamRepositoryProvider).subscribeToPgn(gameId);
});

/// Comprehensive game updates stream for clock times and other live data.
///
/// Uses the SharedGameStreamManager to batch multiple game subscriptions
/// into ONE Realtime channel (instead of one channel per game).
/// This fixes the "ChannelRateLimitReached: Too many channels" error.
final gameUpdatesStreamProvider =
    AutoDisposeStreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  gameId,
) {
  final manager = ref.watch(sharedGameStreamManagerProvider);

  // Clean up when this provider is disposed
  ref.onDispose(() {
    manager.removeGameStream(gameId);
  });

  return manager.getGameStream(gameId);
});
