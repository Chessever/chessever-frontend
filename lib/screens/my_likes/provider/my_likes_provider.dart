import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
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
  const MyLikesFilterState({required this.filter, required this.searchQuery});

  final GameFilter filter;
  final String searchQuery;

  MyLikesFilterState copyWith({GameFilter? filter, String? searchQuery}) {
    return MyLikesFilterState(
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class MyLikesFilterNotifier extends StateNotifier<MyLikesFilterState> {
  MyLikesFilterNotifier()
    : super(
        MyLikesFilterState(filter: GameFilter.defaultFilter(), searchQuery: ''),
      );

  void applyFilter(GameFilter filter) =>
      state = state.copyWith(filter: filter);
  void clearFilter() =>
      state = state.copyWith(filter: GameFilter.defaultFilter());
  void searchGames(String query) => state = state.copyWith(searchQuery: query);
  void clearSearch() => state = state.copyWith(searchQuery: '');
}

final myLikesFilterProvider =
    StateNotifierProvider.autoDispose<MyLikesFilterNotifier, MyLikesFilterState>(
      (ref) => MyLikesFilterNotifier(),
    );

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

int _ratingFromMetadata(MyLikesEntry entry, String key) {
  final value = entry.analysis.chessGame.metadata[key];
  if (value is num) return value.toInt();
  final text = value?.toString() ?? '';
  final digits = RegExp(r'\d+').firstMatch(text)?.group(0);
  return int.tryParse(digits ?? '') ?? 0;
}

int _sortValue(MyLikesEntry entry, GamebaseSortField field) {
  switch (field) {
    case GamebaseSortField.whiteElo:
      return _ratingFromMetadata(entry, 'WhiteElo');
    case GamebaseSortField.blackElo:
      return _ratingFromMetadata(entry, 'BlackElo');
    case GamebaseSortField.avgElo:
      final white = _ratingFromMetadata(entry, 'WhiteElo');
      final black = _ratingFromMetadata(entry, 'BlackElo');
      if (white > 0 && black > 0) return ((white + black) / 2).round();
      return white > 0 ? white : black;
    case GamebaseSortField.date:
      // Use game-played date when available, fall back to liked-at.
      final raw =
          entry.analysis.chessGame.metadata['Date']?.toString().trim() ?? '';
      if (raw.isNotEmpty && raw != '????.??.??') {
        final normalized = raw.replaceAll('.', '-').replaceAll('?', '01');
        final parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.millisecondsSinceEpoch;
      }
      return entry.likedAt.millisecondsSinceEpoch;
  }
}

bool _matchesSearch(MyLikesEntry entry, String queryLower) {
  final md = entry.analysis.chessGame.metadata;
  final haystack = <String>[
    entry.analysis.title,
    entry.game.whitePlayer.name,
    entry.game.blackPlayer.name,
    md['Event']?.toString() ?? '',
    entry.game.eco ?? '',
    entry.game.openingName ?? '',
  ];
  return haystack.any((field) => field.toLowerCase().contains(queryLower));
}

/// The My Likes view, derived from the liked games, the active filter/search,
/// and the subscription state. Returns [AsyncValue] mirroring the liked-games
/// load. All filtering and grouping is client-side over the in-memory list.
final myLikesViewProvider = Provider.autoDispose<AsyncValue<MyLikesData>>((ref) {
  final likedAsync = ref.watch(likedGamesProvider);
  final filterState = ref.watch(myLikesFilterProvider);
  final subscription = ref.watch(subscriptionProvider);

  return likedAsync.whenData((analyses) {
    var entries =
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

    final total = entries.length;

    final query = filterState.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      entries = entries.where((e) => _matchesSearch(e, query)).toList();
    }

    // Filter + sort are premium-only. While the subscription is still
    // resolving (cold start) we treat the user as subscribed so we don't
    // wipe a real premium user's saved filter for a frame.
    final canFilterAndSort =
        subscription.isSubscribed || subscription.isLoading;

    if (canFilterAndSort && filterState.filter.hasActiveFilters) {
      final games = entries.map((e) => e.game).toList();
      final keptIds =
          GameFilterHelper.applyFilter(
            games,
            filterState.filter,
            playerNameQuery: query.isNotEmpty ? query : null,
          ).map((g) => g.gameId).toSet();
      entries = entries.where((e) => keptIds.contains(e.game.gameId)).toList();
    }

    // Sort override (premium only). When a sort is set, flatten the date
    // sections into a single bucket so the chosen order is visible at a
    // glance instead of being shuffled inside per-day groups.
    final sortBy = canFilterAndSort ? filterState.filter.sortBy : null;
    final sortDirection = canFilterAndSort
        ? (filterState.filter.sortDirection ?? GamebaseSortDirection.desc)
        : GamebaseSortDirection.desc;
    final List<MapEntry<String, List<MyLikesEntry>>> sections;
    if (sortBy != null) {
      final sorted = List<MyLikesEntry>.from(entries)..sort((a, b) {
        final comparison =
            _sortValue(a, sortBy).compareTo(_sortValue(b, sortBy));
        final directed = sortDirection == GamebaseSortDirection.asc
            ? comparison
            : -comparison;
        if (directed != 0) return directed;
        return b.likedAt.compareTo(a.likedAt);
      });
      sections = sorted.isEmpty
          ? const <MapEntry<String, List<MyLikesEntry>>>[]
          : [MapEntry('__sorted__', sorted)];
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
});
