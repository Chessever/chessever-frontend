import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How many OTHER people liked a game, keyed by [GamesTourModel.likeId].
///
/// `public.game_like_count` leaves the caller out on purpose: the heart adds
/// the viewer's own like from local liked state, so a tap shows at once and
/// is never counted twice. Null when the count is unknown (the function is
/// not live yet, offline, any error): the button then shows a plain heart
/// rather than a wrong number.
final gameLikeCountProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  likeId,
) async {
  final id = likeId.trim();
  if (id.isEmpty) return null;
  // Keep the count across quick swipes back to the same game, then let it
  // go so a later visit reads a fresh one.
  final link = ref.keepAlive();
  final expiry = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(expiry.cancel);
  try {
    final result = await Supabase.instance.client.rpc(
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

/// The count the heart shows: everyone else, plus the viewer when they like it.
int? displayedGameLikes({required int? others, required bool likedByMe}) =>
    others == null ? null : others + (likedByMe ? 1 : 0);
