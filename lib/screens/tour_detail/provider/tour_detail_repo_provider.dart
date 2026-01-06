import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final tourDetailRepoProvider = AutoDisposeProvider<_TourDetailRepo>((ref) {
  return _TourDetailRepo();
});

class _TourDetailRepo {
  static const _prefix = 'selected_tour_';

  SharedPreferences get _prefs => SharedPreferencesService.instance.prefs;

  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    await _prefs.setString('$_prefix$groupEventId', tourId);
  }

  Future<String?> getSelectedTourId(String groupEventId) async {
    return _prefs.getString('$_prefix$groupEventId');
  }

  /// Optional: clear tourId for a given groupEventId
  Future<void> clearSelectedTourId(String groupEventId) async {
    await _prefs.remove('$_prefix$groupEventId');
  }
}
