import 'dart:ui';

import 'package:chessever2/repository/local_storage/starred_repository/starred_repository.dart';
import 'package:chessever2/screens/tournaments/group_event_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final starredProvider = StateNotifierProvider<_StarredRepository, List<String>>(
  (ref) {
    final currentEvent = ref.watch(selectedGroupCategoryProvider);
    return _StarredRepository(ref: ref, tournamentCategory: currentEvent);
  },
);

class _StarredRepository extends StateNotifier<List<String>> {
  _StarredRepository({required this.ref, required this.tournamentCategory})
    : super([]) {
    init();
  }

  final Ref ref;
  final GroupEventCategory tournamentCategory;

  Future<void> init() async {
    try {
      final key =
          tournamentCategory == GroupEventCategory.upcoming
              ? StarRepoKey.upcomingEvent.name
              : StarRepoKey.liveEvent.name;
      final starredList = await ref.read(starredRepository).getStar(key);
      state = starredList;
    } catch (error, _) {
      rethrow;
    }
  }

  Future<void> toggleStarred(
    String value, {
    VoidCallback? onStarToggled,
  }) async {
    try {
      final currentSaved = List<String>.from(state);
      if (currentSaved.contains(value)) {
        currentSaved.remove(value);
      } else {
        currentSaved.add(value);
      }

      final key =
          tournamentCategory == GroupEventCategory.upcoming
              ? StarRepoKey.upcomingEvent.name
              : StarRepoKey.liveEvent.name;

      await ref.read(starredRepository).toggleStar(key, value);
      state = currentSaved;

      // Refresh the tour list if needed
      if (onStarToggled != null) {
        onStarToggled();
      }
    } catch (error, _) {
      rethrow;
    }
  }

  Future<List<String>> getStarred(String key) async {
    try {
      return state;
    } catch (error, _) {
      rethrow;
    }
  }
}
