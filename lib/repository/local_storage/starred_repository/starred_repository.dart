import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final starredRepository = AutoDisposeProvider<_FavoriteRepository>((ref) {
  return _FavoriteRepository(ref);
});

class _FavoriteRepository {
  _FavoriteRepository(this.ref);

  final Ref ref;

  String _userScopedKey(String key) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return '${key}_guest';
    }
    return '${key}_$userId';
  }

  Future<void> toggleStar(String key, String value) async {
    try {
      final scopedKey = _userScopedKey(key);
      final prefs = ref.read(sharedPreferencesRepository);
      final currentSaved = (await prefs.getStringList(scopedKey)).toList();
      if (currentSaved.contains(value)) {
        currentSaved.remove(value);
      } else {
        currentSaved.add(value);
      }
      await prefs.setStringList(scopedKey, currentSaved);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<List<String>> getStar(String key) async {
    try {
      final scopedKey = _userScopedKey(key);
      final prefs = ref.read(sharedPreferencesRepository);
      return await prefs.getStringList(scopedKey);
    } catch (error, _) {
      rethrow;
    }
  }
}
