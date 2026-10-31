import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repository/gamebase/gamebase_repository.dart';
import 'auth_state_provider.dart';

/// Changing account clears the old account's private video sources immediately.
final gameVideoSourcesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String gameId, String? pgn})>((
      ref,
      key,
    ) async {
      if (key.gameId.isEmpty && (key.pgn == null || key.pgn!.isEmpty)) {
        return const [];
      }
      ref.watch(currentUserProvider);
      return ref
          .read(gamebaseRepositoryProvider)
          .getGameAnalysisVideos(
            gameId: key.gameId,
            pgn: key.pgn,
            bearer: Supabase.instance.client.auth.currentSession?.accessToken,
          );
    });

/// One check per signed-in account: most viewers are neither staff nor
/// collection owners, so no board asks again for them.
final gameVideoViewerRightsProvider =
    FutureProvider<({bool superadmin, bool ownsCollections, bool canAttach})>((
      ref,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null || user.isAnonymous) {
        return (superadmin: false, ownsCollections: false, canAttach: false);
      }
      return ref.read(gamebaseRepositoryProvider).getGameVideoRights();
    });

/// Whether to offer "Attach analysis video" for this game: superadmins on
/// every game, collection owners only on games in their own collections.
final gameVideoAttachRightProvider = FutureProvider.autoDispose
    .family<bool, ({String gameId, String? pgn})>((ref, key) async {
      final viewer = await ref.watch(gameVideoViewerRightsProvider.future);
      if (viewer.superadmin) return true;
      if (!viewer.ownsCollections || key.pgn == null || key.pgn!.isEmpty) {
        return false;
      }
      final rights = await ref
          .read(gamebaseRepositoryProvider)
          .getGameVideoRights(gameId: key.gameId, pgn: key.pgn);
      return rights.canAttach;
    });
