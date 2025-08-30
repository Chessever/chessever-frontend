


import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gameFenStreamProvider = AutoDisposeStreamProvider.family<String?, String>((
    ref,
    gameId,
    ) {
  return ref.read(gameStreamRepositoryProvider).subscribeToFen(gameId);
});
