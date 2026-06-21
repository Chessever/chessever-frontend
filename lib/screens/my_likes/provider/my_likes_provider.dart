import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// One liked game prepared for the My Likes list: the source [analysis], a
/// lightweight card model, when it was liked, and whether it is premium-locked.
class MyLikesEntry {
  const MyLikesEntry({
    required this.analysis,
    required this.game,
    required this.likedAt,
    required this.isLocked,
  });

  final SavedAnalysis analysis;
  final GamesTourModel game;

  /// When the user liked this game (`SavedAnalysis.createdAt`) — the axis the
  /// date sections and the 7-day free-tier window are both keyed on.
  final DateTime likedAt;

  /// True when a free user may not open this game (liked more than 7 days ago).
  final bool isLocked;
}

/// The fully-derived My Likes view: liked-at date sections (newest first), the
/// openable nav list, and counts for the empty/no-match states.
class MyLikesData {
  const MyLikesData({
    required this.sections,
    required this.openableAnalyses,
    required this.totalLiked,
    required this.visibleCount,
  });

  /// `yyyy-MM-dd` (liked-at) → entries, sorted by day descending.
  final List<MapEntry<String, List<MyLikesEntry>>> sections;

  /// Visible order, locked entries excluded — the list handed to the board for
  /// swiping, so the 7-day gate holds even when swiping between games.
  final List<SavedAnalysis> openableAnalyses;

  /// Total likes before search/filter (drives the empty state).
  final int totalLiked;

  /// Entries surviving search + filter (drives the no-match state).
  final int visibleCount;

  bool get isEmpty => totalLiked == 0;
  bool get hasNoMatches => totalLiked > 0 && visibleCount == 0;
}

/// Filter + search state for the My Likes screen. Mirrors the surface the
/// Favorites games tab exposes (apply/clear filter, search/clear) so the same
/// [GameFilter] dialog drives both.
class MyLikesFilterState {
  const MyLikesFilterState({
    required this.filter,
    required this.searchQuery,
    this.selectedTags = const <String>{},
  });

  final GameFilter filter;
  final String searchQuery;

  /// Tag chips selected for filtering. Empty set = no tag filter (the
  /// implicit "all" — there is no dedicated "All" chip anymore).
  final Set<String> selectedTags;

  MyLikesFilterState copyWith({GameFilter? filter, String? searchQuery}) {
    return MyLikesFilterState(
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTags: selectedTags,
    );
  }

  MyLikesFilterState withSelectedTags(Set<String> tags) {
    return MyLikesFilterState(
      filter: filter,
      searchQuery: searchQuery,
      selectedTags: Set<String>.unmodifiable(tags),
    );
  }
}

class MyLikesFilterNotifier extends StateNotifier<MyLikesFilterState> {
  MyLikesFilterNotifier()
    : super(
        MyLikesFilterState(filter: GameFilter.defaultFilter(), searchQuery: ''),
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

final myLikesFilterProvider = StateNotifierProvider.autoDispose<
  MyLikesFilterNotifier,
  MyLikesFilterState
>((ref) => MyLikesFilterNotifier());

final myLikesTagCountsProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final repo = ref.watch(libraryRepositoryProvider);
  // Re-derive the counts whenever the liked list changes (a like/unlike or a
  // tag write), so the quick-filter chips stay current even while the screen
  // is already open — not only on a fresh navigation.
  ref.watch(likedGamesProvider);
  final folder = await ref.watch(likedGamesFolderProvider.future);
  return repo.getTagCountsInFolder(folderId: folder.id);
});

/// Whether a free user may NOT open a game liked at [likedAt].
///
/// Free users may open only games liked within the last 7 calendar days
/// (today + the 6 prior days, in local time). Premium users are never locked.
/// While the subscription is still resolving we treat games as unlocked, to
/// avoid flashing locks at premium users on a cold start.
bool isLikedGameLocked(
  DateTime likedAt, {
  required bool isSubscribed,
  required bool subscriptionLoading,
  DateTime? now,
}) {
  if (isSubscribed || subscriptionLoading) return false;
  final reference = now ?? DateTime.now();
  final todayStart = DateTime(reference.year, reference.month, reference.day);
  final cutoff = todayStart.subtract(const Duration(days: 6));
  final likedDay = DateTime(likedAt.year, likedAt.month, likedAt.day);
  return likedDay.isBefore(cutoff);
}

/// Buckets entries into liked-at day sections, day-descending (newest first).
/// Entry order within a day is preserved (already newest-liked first).
List<MapEntry<String, List<MyLikesEntry>>> groupEntriesByLikedAt(
  List<MyLikesEntry> entries,
) {
  final grouped = <String, List<MyLikesEntry>>{};
  for (final entry in entries) {
    final key = DateFormat('yyyy-MM-dd').format(entry.likedAt);
    grouped.putIfAbsent(key, () => <MyLikesEntry>[]).add(entry);
  }
  final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return keys.map((k) => MapEntry(k, grouped[k]!)).toList();
}

/// The My Likes view, derived from a fresh Supabase query over the liked-games
/// folder plus the active filter/search/tag and subscription state. Filtering
/// is intentionally not performed over the already-downloaded liked-games cache.
final myLikesViewProvider = FutureProvider.autoDispose<MyLikesData>((
  ref,
) async {
  final repo = ref.watch(libraryRepositoryProvider);
  final filterState = ref.watch(myLikesFilterProvider);
  final subscription = ref.watch(subscriptionProvider);
  final folder = await ref.watch(likedGamesFolderProvider.future);

  // Search, filter, sort and tag filtering are all free inside My Likes. The
  // only free-tier restriction is the 7-day read window (`isLikedGameLocked`
  // below); `subscription` is still read for that. So the active filter
  // applies for everyone.
  final effectiveFilter = filterState.filter;

  final results = await Future.wait([
    repo.getLikedAnalysesForView(
      folderId: folder.id,
      filter: effectiveFilter,
      search: filterState.searchQuery,
      tags: filterState.selectedTags.toList(),
    ),
    repo.getOwnedAnalysisCountInFolder(folder.id),
  ]);

  final analyses = results[0] as List<SavedAnalysis>;
  final total = results[1] as int;

  final entries =
      analyses
          .map(
            (analysis) => MyLikesEntry(
              analysis: analysis,
              // Local time so "Today"/the 7-day window match the user's day,
              // not UTC (created_at parses as UTC from Supabase).
              game: savedAnalysisToCardGame(analysis),
              likedAt: analysis.createdAt.toLocal(),
              isLocked: isLikedGameLocked(
                analysis.createdAt.toLocal(),
                isSubscribed: subscription.isSubscribed,
                subscriptionLoading: subscription.isLoading,
              ),
            ),
          )
          .toList();

  // Sort override is already applied in Supabase. Keep the synthetic bucket so
  // a sorted list reads as one ordered result instead of being regrouped by day.
  final sorts = effectiveFilter.sorts;
  final List<MapEntry<String, List<MyLikesEntry>>> sections;
  if (sorts.isNotEmpty) {
    sections =
        entries.isEmpty
            ? const <MapEntry<String, List<MyLikesEntry>>>[]
            : [MapEntry('__sorted__', entries)];
  } else {
    sections = groupEntriesByLikedAt(entries);
  }

  final openable = <SavedAnalysis>[];
  for (final section in sections) {
    for (final entry in section.value) {
      if (!entry.isLocked) openable.add(entry.analysis);
    }
  }

  return MyLikesData(
    sections: sections,
    openableAnalyses: openable,
    totalLiked: total,
    visibleCount: entries.length,
  );
});
