import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Per-folder filter + search state for the database/folder view. Mirrors
/// the My Likes surface ([MyLikesFilterState]) so the same [GameFilter]
/// dialog drives both screens.
class FolderFilterState {
  const FolderFilterState({
    required this.filter,
    required this.searchQuery,
    this.selectedTags = const <String>{},
  });

  final GameFilter filter;
  final String searchQuery;

  /// Tag chips selected for filtering. Empty set = no tag filter (the
  /// implicit "all" — there is no dedicated "All" chip anymore).
  final Set<String> selectedTags;

  FolderFilterState copyWith({GameFilter? filter, String? searchQuery}) {
    return FolderFilterState(
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTags: selectedTags,
    );
  }

  FolderFilterState withSelectedTags(Set<String> tags) {
    return FolderFilterState(
      filter: filter,
      searchQuery: searchQuery,
      selectedTags: Set<String>.unmodifiable(tags),
    );
  }
}

class FolderFilterNotifier extends StateNotifier<FolderFilterState> {
  FolderFilterNotifier()
    : super(
        FolderFilterState(filter: GameFilter.defaultFilter(), searchQuery: ''),
      );

  void applyFilter(GameFilter filter) => state = state.copyWith(filter: filter);
  void clearFilter() =>
      state = state.copyWith(filter: GameFilter.defaultFilter());
  void searchGames(String query) => state = state.copyWith(searchQuery: query);
  void clearSearch() => state = state.copyWith(searchQuery: '');

  /// Toggle a tag in the selection. Empty set after the toggle = implicit
  /// "all games" filter.
  void toggleTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    final next = <String>{...state.selectedTags};
    if (!next.add(trimmed)) next.remove(trimmed);
    state = state.withSelectedTags(next);
  }

  void clearTags() => state = state.withSelectedTags(const <String>{});
}

/// Keyed by `folder.id` so two open folder routes don't cross-pollute filter
/// state, and so the state survives intra-screen rebuilds. Auto-disposes
/// when the route pops and no other widget is watching it.
final folderFilterProvider = StateNotifierProvider.autoDispose
    .family<FolderFilterNotifier, FolderFilterState, String>(
      (ref, folderId) => FolderFilterNotifier(),
    );
