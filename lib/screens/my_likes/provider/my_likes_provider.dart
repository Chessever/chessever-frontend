import 'dart:math' as math;

import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Free users see this many of their most recent likes in My Likes.
///
/// Liking itself is free and unlimited. Everything older than this window
/// stays stored (never deleted, not on overflow and not on downgrade) and is
/// back in full the moment Premium is active.
const int kFreeMyLikesVisibleLimit = 20;

/// Archived likes previewed, locked, under the archive boundary.
const int kMyLikesLockedPreviewCount = 2;

/// Rows PostgREST returns at most for one un-ranged select (the Supabase
/// `max_rows` default). A result this long may be truncated, so a count taken
/// from it is only a lower bound.
const int _kPostgrestMaxRows = 1000;

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

  /// When the user liked this game (`SavedAnalysis.createdAt`, local time):
  /// the axis of both the date sections and the free window.
  final DateTime likedAt;

  /// True when a free user may not open this game: it sits past their latest
  /// [kFreeMyLikesVisibleLimit] likes. Such entries only appear as the locked
  /// preview under the archive boundary.
  final bool isLocked;
}

/// The fully-derived My Likes view: liked-at date sections (newest first), the
/// openable nav list, and counts for the empty/no-match/archive states.
class MyLikesData {
  const MyLikesData({
    required this.sections,
    required this.openableAnalyses,
    required this.totalLiked,
    required this.visibleCount,
    this.archivedCount = 0,
    this.archivedMatchCount = 0,
    this.archivedMatchCountIsExact = true,
    this.isNarrowed = false,
    this.lockedPreview = const <MyLikesEntry>[],
  });

  /// `yyyy-MM-dd` (liked-at) → entries, sorted by day descending. Only the
  /// likes the user may open; archived likes never enter a section.
  final List<MapEntry<String, List<MyLikesEntry>>> sections;

  /// Visible order, locked entries excluded: the list handed to the board for
  /// swiping, so the free window holds even when swiping between games.
  final List<SavedAnalysis> openableAnalyses;

  /// Total likes before search/filter (drives the empty state).
  final int totalLiked;

  /// Openable entries surviving search + filter (drives the no-match state).
  final int visibleCount;

  /// Likes kept past a free user's window (always exact, from the folder
  /// count). Zero for Premium, and while the subscription is resolving.
  final int archivedCount;

  /// Of [archivedCount], how many match the active search/filter/tags. Equal
  /// to [archivedCount] when nothing narrows the list.
  final int archivedMatchCount;

  /// False when [archivedMatchCount] may be truncated and is only a lower
  /// bound, in which case the UI must not print it.
  final bool archivedMatchCountIsExact;

  /// True while a search, filter or tag narrows the list.
  final bool isNarrowed;

  /// The first archived matches in display order, locked, previewed under the
  /// archive boundary.
  final List<MyLikesEntry> lockedPreview;

  bool get isEmpty => totalLiked == 0;

  /// A free user has likes past their window: show the archive boundary.
  bool get showsArchiveBoundary => archivedCount > 0;

  /// Nothing matches anywhere, not even in the archive.
  bool get hasNoMatches =>
      totalLiked > 0 && visibleCount == 0 && archivedMatchCount == 0;
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

/// Newest like first; ties on like time break on id so the free window's
/// edge is deterministic.
int compareLikedNewestFirst(SavedAnalysis a, SavedAnalysis b) {
  final byTime = b.createdAt.compareTo(a.createdAt);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

/// Ids of the likes a free user may open: their latest
/// [kFreeMyLikesVisibleLimit] by like time, whatever the list's current
/// search, filter or sort.
Set<String> freeVisibleLikeIds(
  Iterable<SavedAnalysis> likes, {
  int limit = kFreeMyLikesVisibleLimit,
}) {
  final newestFirst = likes.toList()..sort(compareLikedNewestFirst);
  return {for (final like in newestFirst.take(limit)) like.id};
}

/// Whether My Likes shows every like: Premium, or the entitlement is not
/// known yet (a cold start never flashes a shortened list at a premium user).
///
/// A refresh in flight keeps the last settled answer, so a free user's list
/// does not swell to the full history and back on every app resume. Full
/// visibility returns the moment the entitlement does.
final myLikesUnlimitedProvider =
    NotifierProvider<MyLikesUnlimitedNotifier, bool>(
      MyLikesUnlimitedNotifier.new,
    );

class MyLikesUnlimitedNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen<SubscriptionState>(subscriptionProvider, (_, next) {
      state = next.isSubscribed || (next.isLoading && state);
    });
    final now = ref.read(subscriptionProvider);
    return now.isSubscribed || now.isLoading;
  }
}

/// The free window for this user, or null when nothing is limited (see
/// [myLikesUnlimitedProvider]).
Set<String>? freeLikesWindow(
  Iterable<SavedAnalysis> likes, {
  required bool unlimited,
}) => unlimited ? null : freeVisibleLikeIds(likes);

/// Whether [analysisId] is locked for this user. [window] comes from
/// [freeLikesWindow]; null means nothing is locked.
bool isLikedGameLocked(String analysisId, {required Set<String>? window}) =>
    window != null && !window.contains(analysisId);

/// Whether [analysis] is a like this user can no longer open as their own
/// copy without Premium: it sits in their liked-games folder, older than their
/// latest [kFreeMyLikesVisibleLimit]. For surfaces outside My Likes that still
/// hold the analysis id, such as a My Space pin made while the like was recent.
///
/// [read] is any `ref.read` (widget or provider) or a container's `read`.
Future<bool> isArchivedLike(
  T Function<T>(ProviderListenable<T> provider) read,
  SavedAnalysis analysis,
) async {
  if (read(myLikesUnlimitedProvider)) return false;
  final folder = await read(likedGamesFolderProvider.future);
  if (analysis.folderId != folder.id) return false;
  // The same window query the narrowed My Likes list uses: 20 rows, newest
  // liked first.
  final latest = await read(libraryRepositoryProvider)
      .getSavedAnalysesPaginated(
        folderId: folder.id,
        filter: GameFilter.defaultFilter(),
        limit: kFreeMyLikesVisibleLimit,
      );
  return isLikedGameLocked(
    analysis.id,
    window: freeLikesWindow(latest, unlimited: false),
  );
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

/// Derives the My Likes view from the rows matching the active
/// search/filter/tags ([matches], in display order) and the free [window]
/// (null = unlimited). Pure, so the free-tier rule is testable without a
/// repository or a subscription.
MyLikesData buildMyLikesData({
  required List<SavedAnalysis> matches,
  required int totalLiked,
  required Set<String>? window,
  bool isNarrowed = false,
  bool isSorted = false,
}) {
  final visible = <MyLikesEntry>[];
  final lockedPreview = <MyLikesEntry>[];
  var archivedMatches = 0;

  MyLikesEntry entryFor(SavedAnalysis analysis, {required bool locked}) {
    return MyLikesEntry(
      analysis: analysis,
      game: savedAnalysisToCardGame(analysis),
      // Local time so "Today" matches the user's day, not UTC (created_at
      // parses as UTC from Supabase).
      likedAt: analysis.createdAt.toLocal(),
      isLocked: locked,
    );
  }

  for (final analysis in matches) {
    if (isLikedGameLocked(analysis.id, window: window)) {
      archivedMatches++;
      // Only the previewed few pay for a card model.
      if (lockedPreview.length < kMyLikesLockedPreviewCount) {
        lockedPreview.add(entryFor(analysis, locked: true));
      }
    } else {
      visible.add(entryFor(analysis, locked: false));
    }
  }

  // Sort override is already applied in Supabase. Keep the synthetic bucket so
  // a sorted list reads as one ordered result instead of being regrouped by day.
  final List<MapEntry<String, List<MyLikesEntry>>> sections;
  if (isSorted) {
    sections =
        visible.isEmpty
            ? const <MapEntry<String, List<MyLikesEntry>>>[]
            : [MapEntry('__sorted__', visible)];
  } else {
    sections = groupEntriesByLikedAt(visible);
  }

  final openable = <SavedAnalysis>[
    for (final section in sections)
      for (final entry in section.value) entry.analysis,
  ];

  final archived =
      window == null ? 0 : math.max(0, totalLiked - window.length);

  return MyLikesData(
    sections: sections,
    openableAnalyses: openable,
    totalLiked: totalLiked,
    visibleCount: visible.length,
    archivedCount: archived,
    // Un-narrowed, every archived like "matches"; the folder count is exact
    // even when the row list was truncated.
    archivedMatchCount: isNarrowed ? archivedMatches : archived,
    archivedMatchCountIsExact:
        !isNarrowed || matches.length < _kPostgrestMaxRows,
    isNarrowed: isNarrowed,
    lockedPreview: archived > 0 ? lockedPreview : const <MyLikesEntry>[],
  );
}

/// The My Likes view, derived from a fresh Supabase query over the liked-games
/// folder plus the active filter/search/tag and subscription state. Filtering
/// is intentionally not performed over the already-downloaded liked-games cache.
final myLikesViewProvider = FutureProvider.autoDispose<MyLikesData>((
  ref,
) async {
  final repo = ref.watch(libraryRepositoryProvider);
  final filterState = ref.watch(myLikesFilterProvider);
  // Only the entitlement matters here; offerings loads must not refetch.
  final unlimited = ref.watch(myLikesUnlimitedProvider);
  final folder = await ref.watch(likedGamesFolderProvider.future);

  // Search, filter, sort and tag filtering are all free inside My Likes. The
  // only free-tier restriction is the window of the latest
  // [kFreeMyLikesVisibleLimit] likes, so the active filter applies for everyone.
  final filter = filterState.filter;
  final isNarrowed =
      filter.hasActiveFilters ||
      filterState.searchQuery.trim().isNotEmpty ||
      filterState.selectedTags.isNotEmpty;

  // The free window is the latest likes by like time, independent of what the
  // list currently shows. A narrowed or re-sorted result cannot say which likes
  // are the newest, so fetch that window directly (20 rows, newest first).
  final needsWindowQuery = !unlimited && (isNarrowed || filter.hasActiveSorts);

  final results = await Future.wait([
    repo.getLikedAnalysesForView(
      folderId: folder.id,
      filter: filter,
      search: filterState.searchQuery,
      tags: filterState.selectedTags.toList(),
    ),
    repo.getOwnedAnalysisCountInFolder(folder.id),
    if (needsWindowQuery)
      repo.getSavedAnalysesPaginated(
        folderId: folder.id,
        filter: GameFilter.defaultFilter(),
        limit: kFreeMyLikesVisibleLimit,
      ),
  ]);

  final matches = results[0] as List<SavedAnalysis>;
  final total = results[1] as int;
  final windowSource =
      needsWindowQuery ? results[2] as List<SavedAnalysis> : matches;

  return buildMyLikesData(
    matches: matches,
    totalLiked: total,
    window: freeLikesWindow(windowSource, unlimited: unlimited),
    isNarrowed: isNarrowed,
    isSorted: filter.hasActiveSorts,
  );
});
