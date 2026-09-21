import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';

/// Tokens distinguish multiple mounted presentations of the same game.
final visibleTournamentCardsProvider = StateProvider<Map<Object, String>>(
  (ref) => const {},
);

final _visibleBatchProvider = Provider.autoDispose
    .family<LiveGamesBatchKey, LiveGamesBatchKey>((ref, batch) {
      final visible = ref.watch(visibleTournamentCardsProvider).values.toSet();
      return LiveGamesBatchKey(
        scopeId: 'viewport:${batch.scopeId}',
        gameIds: batch.gameIds.where(visible.contains),
      );
    });

/// Other screens can continue to use their own subscription policy.
class TournamentCardViewport extends InheritedWidget {
  const TournamentCardViewport({super.key, required super.child});

  @override
  bool updateShouldNotify(TournamentCardViewport oldWidget) => false;
}

LiveGamesBatchKey? watchVisibleTournamentBatch(
  WidgetRef ref,
  LiveGamesBatchKey? batch,
) {
  if (batch == null ||
      ref.context
              .dependOnInheritedWidgetOfExactType<TournamentCardViewport>() ==
          null) {
    return batch;
  }
  return ref.watch(_visibleBatchProvider(batch));
}
