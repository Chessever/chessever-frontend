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
