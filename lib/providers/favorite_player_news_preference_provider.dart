import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/favorite_player_news_preference_store.dart';
import 'package:flutter/foundation.dart';
import '../services/direct_push_service.dart';
import '../services/direct_push_registration_controller.dart';

final favoritePlayerNewsStoreProvider = Provider(
  (ref) => FavoritePlayerNewsPreferenceStore(),
);
final favoritePlayerNewsSyncProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => DirectPushService.instance.syncNewsPreference(),
);
final favoritePlayerNewsStatusProvider =
    Provider<ValueListenable<FavoritePlayerNewsSyncStatus>>(
      (ref) => DirectPushService.instance.newsSyncStatus,
    );
final favoritePlayerNewsPreferenceProvider =
    AsyncNotifierProvider<FavoritePlayerNewsPreferenceNotifier, bool>(
      FavoritePlayerNewsPreferenceNotifier.new,
    );

class FavoritePlayerNewsPreferenceNotifier extends AsyncNotifier<bool> {
  Future<void> _writes = Future.value();
  @override
  Future<bool> build() => ref.read(favoritePlayerNewsStoreProvider).read();

  Future<void> setEnabled(bool enabled) {
    // Serialize rapid toggles so an older save cannot restore a newer opt-out.
    final next = _writes.catchError((Object _) {}).then((_) async {
      await ref.read(favoritePlayerNewsStoreProvider).write(enabled);
      state = AsyncData(enabled);
    });
    _writes = next;
    return next.then((_) => ref.read(favoritePlayerNewsSyncProvider)());
  }
}
