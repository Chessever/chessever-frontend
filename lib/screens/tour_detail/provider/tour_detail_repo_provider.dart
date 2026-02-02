import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourDetailRepoProvider = AutoDisposeProvider<_TourDetailRepo>((ref) {
  return _TourDetailRepo();
});

class _TourDetailRepo {
  static const _prefix = 'selected_tour_';

  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    final db = AppDatabase.instance;
    await db.setString('$_prefix$groupEventId', tourId);
  }

  Future<String?> getSelectedTourId(String groupEventId) async {
    final db = AppDatabase.instance;
    return await db.getString('$_prefix$groupEventId');
  }

  /// Optional: clear tourId for a given groupEventId
  Future<void> clearSelectedTourId(String groupEventId) async {
    final db = AppDatabase.instance;
    await db.remove('$_prefix$groupEventId');
  }
}
