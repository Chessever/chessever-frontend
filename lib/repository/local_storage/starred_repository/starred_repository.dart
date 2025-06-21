import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final starredRepository = AutoDisposeProvider<_FavoriteRepository>((ref) {
  return _FavoriteRepository(ref);
});

enum StarRepoKey { upcomingEvent, liveEvent }

class _FavoriteRepository {
  _FavoriteRepository(this.ref);

  final Ref ref;

  Future<void> toggleStar(String key, String value) async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      final currentSaved = (await prefs.getStringList(key)).toList();
      if (currentSaved.contains(value)) {
        currentSaved.remove(value);
      } else {
        currentSaved.add(value);
      }
      prefs.setStringList(key, currentSaved);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<List<String>> getStar(String key) async {
    try {
      final prefs = ref.read(sharedPreferencesRepository);
      return await prefs.getStringList(key);
    } catch (error, _) {
      rethrow;
    }
  }
}
