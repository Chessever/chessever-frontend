import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Per-folder filter + search state for the database/folder view. Mirrors
/// the My Likes surface ([MyLikesFilterState]) so the same [GameFilter]
/// dialog drives both screens.
class FolderFilterState {
  const FolderFilterState({required this.filter, required this.searchQuery});

  final GameFilter filter;
  final String searchQuery;

  FolderFilterState copyWith({GameFilter? filter, String? searchQuery}) {
    return FolderFilterState(
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class FolderFilterNotifier extends StateNotifier<FolderFilterState> {
  FolderFilterNotifier()
    : super(
        FolderFilterState(
          filter: GameFilter.defaultFilter(),
          searchQuery: '',
        ),
      );

  void applyFilter(GameFilter filter) =>
      state = state.copyWith(filter: filter);
  void clearFilter() =>
      state = state.copyWith(filter: GameFilter.defaultFilter());
  void searchGames(String query) => state = state.copyWith(searchQuery: query);
  void clearSearch() => state = state.copyWith(searchQuery: '');
}

/// Keyed by `folder.id` so two open folder routes don't cross-pollute filter
/// state, and so the state survives intra-screen rebuilds. Auto-disposes
/// when the route pops and no other widget is watching it.
final folderFilterProvider = StateNotifierProvider.autoDispose
    .family<FolderFilterNotifier, FolderFilterState, String>(
  (ref, folderId) => FolderFilterNotifier(),
);
