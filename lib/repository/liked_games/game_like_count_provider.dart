import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A game's like count, keyed by [GamesTourModel.likeId], straight from the
/// server (`public.game_like_count`, the same like definition Discovery ranks
/// by). Read again whenever a like write lands, so the viewer's own like
/// shows once the server holds it. Null when unknown (signed out, offline,
/// any error): the button then shows a plain heart rather than a wrong number.
final gameLikeCountProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  likeId,
) async {
  ref.watch(likedGamesWriteRevisionProvider);
  final id = likeId.trim();
  final client = Supabase.instance.client;
  if (id.isEmpty || client.auth.currentSession == null) return null;
  try {
    final result = await client.rpc(
      'game_like_count',
      params: {'p_source_game_id': id},
    );
    return parseGameLikeCount(result);
  } catch (error) {
    debugPrint('[LikeCount] $id failed: $error');
    return null;
  }
});

/// The RPC answers a bare bigint, which PostgREST may send as a number or a
/// numeric string.
@visibleForTesting
int? parseGameLikeCount(Object? raw) {
  final value = switch (raw) {
    int v => v,
    num v when v.isFinite => v.toInt(),
    String v => int.tryParse(v.trim()),
    _ => null,
  };
  return value == null || value < 0 ? null : value;
}
