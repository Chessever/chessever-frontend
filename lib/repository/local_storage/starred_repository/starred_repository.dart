import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final starredRepository = AutoDisposeProvider<_FavoriteRepository>((ref) {
  return _FavoriteRepository(ref);
});

class _FavoriteRepository {
  _FavoriteRepository(this.ref);

  final Ref ref;

  String? _getCurrentUserId() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return null; // guest user
    }
    return userId;
  }

  Future<void> toggleStar(String key, String value) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final userId = _getCurrentUserId();
      final contains = await db.listContains(
        key: 'starred_$key',
        item: value,
        userId: userId,
      );

      if (contains) {
        await db.removeFromList(
          key: 'starred_$key',
          item: value,
          userId: userId,
        );
      } else {
        await db.addToList(key: 'starred_$key', item: value, userId: userId);
      }
    } catch (error, _) {
      // Local storage failure is not critical
    }
  }

  Future<List<String>> getStar(String key) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final userId = _getCurrentUserId();
      return await db.getList(key: 'starred_$key', userId: userId);
    } catch (error, _) {
      // Local storage failure - return empty list
      return [];
    }
  }
}
