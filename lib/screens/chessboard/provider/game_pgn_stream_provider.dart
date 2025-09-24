import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamePgnStreamProvider = AutoDisposeStreamProvider.family<String?, String>((
  ref,
  gameId,
) {
  return ref.read(gameStreamRepositoryProvider).subscribeToPgn(gameId);
});

// Comprehensive game updates stream for clock times and other live data
final gameUpdatesStreamProvider = AutoDisposeStreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  gameId,
) {
  return ref.read(gameStreamRepositoryProvider).subscribeToGameUpdates(gameId);
});
