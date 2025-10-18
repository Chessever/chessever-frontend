import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final tourDetailRepoProvider = AutoDisposeProvider<_TourDetailRepo>((ref) {
  return _TourDetailRepo();
});

class _TourDetailRepo {
  static const _prefix = 'selected_tour_';

  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$groupEventId', tourId);
  }

  Future<String?> getSelectedTourId(String groupEventId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$groupEventId');
  }

  /// Optional: clear tourId for a given groupEventId
  Future<void> clearSelectedTourId(String groupEventId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$groupEventId');
  }
}
