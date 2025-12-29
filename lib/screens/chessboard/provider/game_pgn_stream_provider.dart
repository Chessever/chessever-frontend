import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stream provider for PGN updates of a specific game.
/// Auto-disposes when the widget is no longer in view.
final gamePgnStreamProvider =
    AutoDisposeStreamProvider.family<String?, String>((
  ref,
  gameId,
) {
  return ref.read(gameStreamRepositoryProvider).subscribeToPgn(gameId);
});

/// Comprehensive game updates stream for live data (FEN, PGN, clocks, status).
///
/// Each game gets its own individual Realtime channel.
/// Auto-disposes when the widget is scrolled out of view, which automatically
/// cleans up the Supabase Realtime subscription.
final gameUpdatesStreamProvider =
    AutoDisposeStreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  gameId,
) {
  return ref.read(gameStreamRepositoryProvider).subscribeToGameUpdates(gameId);
});
