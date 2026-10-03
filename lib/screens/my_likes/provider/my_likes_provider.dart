import 'dart:async';

import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';

import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Free users open this many of their most recent likes straight from My
/// Likes.
///
/// Liking itself is free and unlimited, and every like is listed for
/// everyone. A like older than this window stays in the list, opens through
/// the Premium guard, and opens freely the moment Premium is active.
const int kFreeMyLikesVisibleLimit = 20;

/// The upgrade hand-off's feature id for an older like opened from a locked
/// card. A fixed identifier for the paywall analytics, never user data.
const String kMyLikesHistoryFeatureId = 'my_likes_history';

/// The upgrade hand-off's feature id for exporting every like as PGN.
const String kMyLikesExportFeatureId = 'my_likes_export';

/// The surface My Likes gates resume on once the viewer is entitled.
const String kMyLikesReturnTo = 'my_likes';

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
  /// [kFreeMyLikesVisibleLimit] likes. It is listed where it belongs, and
  /// opens through the Premium guard.
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
    this.isNarrowed = false,
  });

  /// `yyyy-MM-dd` (liked-at) → entries, sorted by day descending. Every like
  /// matching the search and filters, the same list for everyone.
  final List<MapEntry<String, List<MyLikesEntry>>> sections;

  /// Visible order, locked entries excluded: the list handed to the board for
  /// swiping, so the free window holds even when swiping between games.
  final List<SavedAnalysis> openableAnalyses;

  /// Total likes before search/filter (drives the empty state).
  final int totalLiked;

  /// Entries surviving search + filter (drives the no-match state).
  final int visibleCount;

  /// True while a search, filter or tag narrows the list.
  final bool isNarrowed;

  bool get isEmpty => totalLiked == 0;

  /// Nothing matches the search and filters.
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

final myLikesFilterProvider =
    StateNotifierProvider.autoDispose<
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

/// Whether every like opens freely: Premium, or the entitlement is not
/// known yet (a cold start never flashes locks at a premium user).
///
/// A refresh in flight keeps the last settled answer, so a free user's locks
/// do not lift and return on every app resume. They lift for good the moment
/// the entitlement does.
final myLikesUnlimitedProvider =
    NotifierProvider<MyLikesUnlimitedNotifier, bool>(
      MyLikesUnlimitedNotifier.new,
    );

class MyLikesUnlimitedNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen<SubscriptionState>(featureAccessStateProvider, (_, next) {
      state = next.isSubscribed || (next.isLoading && state);
    });
    final now = ref.read(featureAccessStateProvider);
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
/// (null = unlimited): the same list for everyone, with the likes past the
/// window marked locked. Pure, so the free-tier rule is testable without a
/// repository or a subscription.
MyLikesData buildMyLikesData({
  required List<SavedAnalysis> matches,
  required int totalLiked,
  required Set<String>? window,
  bool isNarrowed = false,
  bool isSorted = false,
}) {
  // Every match is listed, in the order it came; a like past the free window
  // only carries its lock.
  final visible = <MyLikesEntry>[
    for (final analysis in matches)
      MyLikesEntry(
        analysis: analysis,
        game: savedAnalysisToCardGame(analysis),
        // Local time so "Today" matches the user's day, not UTC (created_at
        // parses as UTC from Supabase).
        likedAt: analysis.createdAt.toLocal(),
        isLocked: isLikedGameLocked(analysis.id, window: window),
      ),
  ];

  // Sort override is already applied in Supabase. Keep the synthetic bucket so
  // a sorted list reads as one ordered result instead of being regrouped by day.
  final List<MapEntry<String, List<MyLikesEntry>>> sections;
  if (isSorted) {
    sections = visible.isEmpty
        ? const <MapEntry<String, List<MyLikesEntry>>>[]
        : [MapEntry('__sorted__', visible)];
  } else {
    sections = groupEntriesByLikedAt(visible);
  }

  final openable = <SavedAnalysis>[
    for (final section in sections)
      for (final entry in section.value)
        if (!entry.isLocked) entry.analysis,
  ];

  return MyLikesData(
    sections: sections,
    openableAnalyses: openable,
    totalLiked: totalLiked,
    visibleCount: visible.length,
    isNarrowed: isNarrowed,
  );
}

/// The My Likes view, derived from a fresh Supabase query over the liked-games
/// folder plus the active filter/search/tag and subscription state. Filtering
/// is intentionally not performed over the already-downloaded liked-games cache.
///
/// It runs again whenever a like, an unlike or a tag write has settled on the
/// server ([likedGamesWriteRevisionProvider]): a like still being saved when
/// the screen opened appears by itself, and a change made on a board opened
/// from here shows on return. It follows the settled writes, not the session
/// list, so it never refetches on an optimistic unlike before its delete lands.
final myLikesViewProvider = FutureProvider.autoDispose<MyLikesData>((
  ref,
) async {
  ref.watch(likedGamesWriteRevisionProvider);
  final repo = ref.watch(libraryRepositoryProvider);
  final filterState = ref.watch(myLikesFilterProvider);
  // Only the entitlement matters here; offerings loads must not refetch.
  final unlimited = ref.watch(myLikesUnlimitedProvider);
  final folder = await ref.watch(likedGamesFolderProvider.future);

  // Search, filter, sort and tag filtering are all free inside My Likes, and
  // every like is listed. The only free-tier restriction is which likes open
  // freely: the latest [kFreeMyLikesVisibleLimit].
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
  final windowSource = needsWindowQuery
      ? results[2] as List<SavedAnalysis>
      : matches;

  return buildMyLikesData(
    matches: matches,
    totalLiked: total,
    window: freeLikesWindow(windowSource, unlimited: unlimited),
    isNarrowed: isNarrowed,
    isSorted: filter.hasActiveSorts,
  );
});

/// Re-reads everything My Likes draws from, after a liked row itself was
/// changed outside the like path: "Move to database" takes it out of the liked
/// folder, "Edit & annotate" rewrites it. The session list and the view both
/// refresh, so the card is redrawn, or leaves, at once.
///
/// Takes the container rather than a widget's `ref`: the card that raised the
/// menu may be gone by the time the action reports back.
void refreshMyLikes(ProviderContainer container) {
  unawaited(container.read(likedGamesProvider.notifier).refresh());
  container.invalidate(myLikesViewProvider);
  container.invalidate(myLikesTagCountsProvider);
}
