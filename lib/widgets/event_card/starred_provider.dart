import 'package:chessever2/repository/local_storage/starred_repository/starred_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final starredProvider =
    StateNotifierProvider.family<_StarredRepository, List<String>, String>((
      ref,
      tournamentKey,
    ) {
      return _StarredRepository(ref: ref, tournamentKey: tournamentKey);
    });

class _StarredRepository extends StateNotifier<List<String>> {
  _StarredRepository({required this.ref, required this.tournamentKey})
    : super(<String>[]) {
    init();
  }

  final Ref ref;
  final String tournamentKey;

  Future<void> init() async {
    try {
      final starredList = await ref
          .read(starredRepository)
          .getStar(tournamentKey);
      state = starredList;
    } catch (error, _) {
      rethrow;
    }
  }

  Future<void> toggleStarred(String value) async {
    try {
      final currentSaved = List<String>.from(state);
      if (currentSaved.contains(value)) {
        currentSaved.remove(value);
      } else {
        currentSaved.add(value);
      }

      await ref.read(starredRepository).toggleStar(tournamentKey, value);
      state = currentSaved;
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
