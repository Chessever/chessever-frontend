import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Active query for the Miniatures screen (window + sort + search + filters).
final miniaturesFilterProvider =
    StateProvider.autoDispose<MiniatureGamesFilter>(
      (ref) => MiniatureGamesFilter.defaultFilter,
    );

/// Total number of miniatures in the community index (unfiltered).
/// Backs the "N miniatures" subtitle on the Library card.
final miniaturesTotalCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.read(gamebaseRepositoryProvider);
  final page = await repo.getMiniatures(limit: 1);
  return page.total;
});

/// Board-ready view of the loaded miniatures. Mapped once per page load
/// instead of on every rebuild, since the Games tab regroups this list on
/// every expand/collapse.
final miniatureGamesProvider = Provider.autoDispose<List<GamesTourModel>>((
  ref,
) {
  final items = ref.watch(miniaturesPaginatedProvider).items;
  return items.map((item) => item.toGamesTourModel()).toList(growable: false);
});

/// Aggregate stats behind the About tab, keyed by the time window the user
/// picked there. Independent of the Games tab filter on purpose: About
/// describes the whole index, not whatever the list is narrowed to.
///
/// Fetched at the backend's max limits (90 daily points, 50 openings, 20
/// notable games each side) so the compact About-tab previews AND the
/// openings/rhythm/hall-of-fame detail screens all read from this one cached
/// result per window — drilling in never re-fetches.
final miniatureStatsProvider = FutureProvider.autoDispose
    .family<MiniatureStats, MiniatureGamesWindow>((ref, window) async {
      final repo = ref.read(gamebaseRepositoryProvider);
      return repo.getMiniatureStats(
        filter: MiniatureGamesFilter.defaultFilter.copyWith(window: window),
        // The daily series can only ever span the window itself, so asking for
        // more than that would report a per-day average from padded zeros.
        dailyDays: switch (window) {
          MiniatureGamesWindow.today => 1,
          MiniatureGamesWindow.week => 7,
          MiniatureGamesWindow.all => 90,
        },
        openingLimit: 50,
        notableLimit: 20,
      );
    });

/// Query state for the Players tab: title chips + sort + name search.
class MiniaturePlayersQuery {
  const MiniaturePlayersQuery({
    this.titles = const <MiniaturePlayerTitle>{},
    this.sort = MiniaturePlayerSort.games,
    this.search,
  });

  final Set<MiniaturePlayerTitle> titles;
  final MiniaturePlayerSort sort;
  final String? search;

  /// Count shown on the filter-dialog badge (title chips + sort, desktop
  /// parity with the Games tab's own combined filter/sort dialog).
  int get activeFilterCount {
    var count = 0;
    if (titles.isNotEmpty) count += 1;
    if (sort != MiniaturePlayerSort.games) count += 1;
    return count;
  }

  bool get hasActiveFilters => activeFilterCount > 0;

  MiniaturePlayersQuery copyWith({
    Set<MiniaturePlayerTitle>? titles,
    MiniaturePlayerSort? sort,
    String? search,
    bool clearSearch = false,
  }) {
    return MiniaturePlayersQuery(
      titles: titles ?? this.titles,
      sort: sort ?? this.sort,
      search: clearSearch ? null : (search ?? this.search),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MiniaturePlayersQuery &&
        other.sort == sort &&
        other.search == search &&
        other.titles.length == titles.length &&
        other.titles.containsAll(titles);
  }

  @override
  int get hashCode =>
      Object.hash(sort, search, Object.hashAllUnordered(titles));
}

final miniaturePlayersQueryProvider =
    StateProvider.autoDispose<MiniaturePlayersQuery>(
      (ref) => const MiniaturePlayersQuery(),
    );

class MiniaturePlayersState {
  const MiniaturePlayersState({
    this.items = const <MiniaturePlayer>[],
    this.totalCount = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final List<MiniaturePlayer> items;
  final int totalCount;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  MiniaturePlayersState copyWith({
    List<MiniaturePlayer>? items,
    int? totalCount,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return MiniaturePlayersState(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Offset-paginated player leaderboard. Recreated whenever the query changes,
/// mirroring [miniaturesPaginatedProvider].
final miniaturePlayersPaginatedProvider = StateNotifierProvider.autoDispose<
  MiniaturePlayersNotifier,
  MiniaturePlayersState
>((ref) {
  final query = ref.watch(miniaturePlayersQueryProvider);
  return MiniaturePlayersNotifier(ref, query);
});

class MiniaturePlayersNotifier extends StateNotifier<MiniaturePlayersState> {
  MiniaturePlayersNotifier(this._ref, this._query)
    : super(const MiniaturePlayersState(isLoading: true)) {
    _fetchPage(reset: true);
  }

  /// Keep the first paint light: each row also triggers a photo lookup, so
  /// a smaller page avoids a stampede of concurrent image requests.
  static const int _pageSize = 20;

  final Ref _ref;
  final MiniaturePlayersQuery _query;
  int _requestSeq = 0;

  Future<void> refresh() => _fetchPage(reset: true);

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPage(reset: false);
  }

  Future<void> _fetchPage({required bool reset}) async {
    final seq = ++_requestSeq;
    final offset = reset ? 0 : state.items.length;
    // On reset keep any already-shown rows so pull-to-refresh does not flash
    // an empty shimmer; only the initial empty state shows skeletons.
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repo = _ref.read(gamebaseRepositoryProvider);
      final page = await repo.getMiniaturePlayers(
        sort: _query.sort,
        titles: _query.titles,
        search: _query.search,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || seq != _requestSeq) return;

      final items =
          reset ? page.items : <MiniaturePlayer>[...state.items, ...page.items];
      // Prefer page-length for hasMore: backend may return an approximate total
      // (avoids a second full aggregate). A short page always means the end.
      final hasMore = page.items.length >= _pageSize;
      state = state.copyWith(
        items: items,
        totalCount: page.total,
        isLoading: false,
        hasMore: hasMore,
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted || seq != _requestSeq) return;
      state = state.copyWith(
        isLoading: false,
        // Keep already-loaded rows; only stop paging on failure.
        hasMore: reset ? false : state.hasMore,
        error: e.toString(),
      );
    }
  }
}

class MiniaturesPaginationState {
  const MiniaturesPaginationState({
    this.items = const <GamebaseMiniature>[],
    this.totalCount = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final List<GamebaseMiniature> items;
  final int totalCount;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  MiniaturesPaginationState copyWith({
    List<GamebaseMiniature>? items,
    int? totalCount,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return MiniaturesPaginationState(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Offset-paginated miniatures for the active filter. The provider is
/// recreated whenever [miniaturesFilterProvider] changes, so each notifier
/// serves exactly one query.
final miniaturesPaginatedProvider = StateNotifierProvider.autoDispose<
  MiniaturesPaginationNotifier,
  MiniaturesPaginationState
>((ref) {
  final filter = ref.watch(miniaturesFilterProvider);
  return MiniaturesPaginationNotifier(ref, filter);
});

class MiniaturesPaginationNotifier
    extends StateNotifier<MiniaturesPaginationState> {
  MiniaturesPaginationNotifier(this._ref, this._filter)
    : super(const MiniaturesPaginationState(isLoading: true)) {
    _fetchPage(reset: true);
  }

  static const int _pageSize = 50;

  final Ref _ref;
  final MiniatureGamesFilter _filter;
  int _requestSeq = 0;

  Future<void> refresh() => _fetchPage(reset: true);

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPage(reset: false);
  }

  Future<void> _fetchPage({required bool reset}) async {
    final seq = ++_requestSeq;
    final offset = reset ? 0 : state.items.length;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repo = _ref.read(gamebaseRepositoryProvider);
      final page = await repo.getMiniatures(
        filter: _filter,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted || seq != _requestSeq) return;

      final items =
          reset
              ? page.items
              : <GamebaseMiniature>[...state.items, ...page.items];
      state = state.copyWith(
        items: items,
        totalCount: page.total,
        isLoading: false,
        hasMore: items.length < page.total && page.items.isNotEmpty,
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted || seq != _requestSeq) return;
      state = state.copyWith(
        isLoading: false,
        // Keep already-loaded rows; surface the error only for the empty case.
        hasMore: false,
        error: e.toString(),
      );
    }
  }
}

/// Active filter for one player's miniature scorecard, keyed by the
/// gamebase player uuid. Seeded with that scope every time the family member
/// is first created, so `.family` gives each player their own independent
/// filter state instead of sharing [miniaturesFilterProvider].
final miniaturePlayerGamesFilterProvider = StateProvider.autoDispose
    .family<MiniatureGamesFilter, String>(
      (ref, playerId) =>
          MiniatureGamesFilter.defaultFilter.copyWith(playerId: playerId),
    );

/// Offset-paginated miniatures for one player's scorecard screen. Reuses
/// [MiniaturesPaginationNotifier] as-is — the only difference from
/// [miniaturesPaginatedProvider] is the `playerId`-scoped filter it watches.
final miniaturePlayerGamesPaginatedProvider = StateNotifierProvider.autoDispose
    .family<MiniaturesPaginationNotifier, MiniaturesPaginationState, String>((
      ref,
      playerId,
    ) {
      final filter = ref.watch(miniaturePlayerGamesFilterProvider(playerId));
      return MiniaturesPaginationNotifier(ref, filter);
    });

/// Board-ready view of one player's loaded miniatures, mirroring
/// [miniatureGamesProvider] for the `.family`-scoped scorecard screen.
final miniaturePlayerGamesProvider = Provider.autoDispose
    .family<List<GamesTourModel>, String>((ref, playerId) {
      final items =
          ref.watch(miniaturePlayerGamesPaginatedProvider(playerId)).items;
      return items
          .map((item) => item.toGamesTourModel())
          .toList(growable: false);
    });
