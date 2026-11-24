import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/liked_games/like_realtime.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _likeSessionProvider =
    Provider<({SupabaseClient client, String userId})?>((ref) {
      ref.watch(currentUserProvider.select((user) => user?.id));
      try {
        final supabase = Supabase.instance;
        if (!supabase.isInitialized) return null;
        final client = supabase.client;
        final userId = client.auth.currentSession?.user.id;
        return userId == null ? null : (client: client, userId: userId);
      } on AssertionError {
        // Feed can render before Supabase is initialized.
        return null;
      }
    });

final _likeChangesProvider = StreamProvider.autoDispose.family<int, String>((
  ref,
  likeId,
) {
  final client = ref.watch(_likeSessionProvider)?.client;
  if (client == null || likeId.isEmpty) return const Stream.empty();
  return gameLikeChanges(client, likeId);
});

typedef _LikeSummary = ({int count, bool? liked});

final _likeSummaryProvider = FutureProvider.autoDispose
    .family<_LikeSummary?, String>((ref, likeId) async {
      ref.watch(
        _likeChangesProvider(likeId).select((value) => value.valueOrNull),
      );
      ref.watch(likedGamesWriteRevisionProvider);
      final client = ref.watch(_likeSessionProvider)?.client;
      if (client == null || likeId.isEmpty) return null;
      try {
        Object? raw;
        try {
          raw = await client.rpc(
            'game_like_summary',
            params: {'p_source_game_id': likeId},
          );
        } on PostgrestException catch (error) {
          if (error.code != 'PGRST202') rethrow;
          // Keep the old count during a staggered rollout.
          final count = parseGameLikeCount(
            await client.rpc(
              'game_like_count',
              params: {'p_source_game_id': likeId},
            ),
          );
          return count == null ? null : (count: count, liked: null);
        }
        if (raw is! Map || raw['liked'] is! bool) return null;
        final count = parseGameLikeCount(raw['count']);
        return count == null
            ? null
            : (count: count, liked: raw['liked'] as bool);
      } catch (error) {
        debugPrint('[LikeCount] $likeId failed: $error');
        return null;
      }
    });

/// The server's count of other accounts plus this account's local heart.
final gameLikeCountProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  likeId,
) async {
  final id = likeId.trim();
  if (ref.watch(_likeSessionProvider) == null || id.isEmpty) {
    return null;
  }
  final pending = ref.watch(isGameLikePendingProvider(id));
  final local = ref.watch(
    likedGamesProvider.select(
      (value) => value.valueOrNull?.any((row) => row.sourceGameId == id),
    ),
  );
  final summary = ref.watch(_likeSummaryProvider(id));
  final snapshot = summary.hasValue
      ? summary.valueOrNull
      : await ref.watch(_likeSummaryProvider(id).future);
  if (snapshot == null) return null;
  final serverLiked = snapshot.liked;
  if (serverLiked == null || (local == null && !pending)) return snapshot.count;
  final others = snapshot.count - (serverLiked ? 1 : 0);
  return others + (pending || local == true ? 1 : 0);
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
