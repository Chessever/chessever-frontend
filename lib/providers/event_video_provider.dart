import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../screens/chessboard/video/video_metadata_cache.dart';
import '../screens/chessboard/video/video_repository.dart';
import '../screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';

export '../screens/chessboard/video/video_metadata_cache.dart'
    show EventVideoKey;

final eventVideoConfigurationProvider = Provider<EventVideoConfiguration?>(
  (ref) => EventVideoConfiguration.fromEnvironment(),
);

/// Kept for the ProviderScope lifetime, including when no board is open.
final eventVideoMetadataProvider =
    ChangeNotifierProvider<EventVideoMetadataCache>((ref) {
      final config = ref.watch(eventVideoConfigurationProvider);
      final cache = EventVideoMetadataCache(
        config == null ? null : HttpEventVideoRepository(config),
      );
      return cache;
    });

/// Watching this at the app root starts metadata discovery before navigation.
/// It does not subscribe the app's widget tree to individual URL refreshes.
final eventVideoPreloadProvider = Provider<void>((ref) {
  final cache = ref.watch(eventVideoMetadataProvider.notifier);
  if (!cache.enabled) return;
  final lifecycle = AppLifecycleListener(
    onStateChange:
        (state) => cache.setForeground(state == AppLifecycleState.resumed),
  );
  final state = WidgetsBinding.instance.lifecycleState;
  cache.setForeground(state == null || state == AppLifecycleState.resumed);
  ref.onDispose(lifecycle.dispose);
  ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (_, next) {
    final rounds = next.valueOrNull;
    if (rounds != null) cache.setLiveRounds(rounds);
  }, fireImmediately: true);
});

/// Game lists register scopes without rebuilding cards on metadata changes.
final eventVideoScopePreloadProvider = Provider.autoDispose
    .family<void, EventVideoKey>((ref, key) {
      final cache = ref.watch(eventVideoMetadataProvider.notifier);
      ref.onDispose(cache.retain(key));
    });
