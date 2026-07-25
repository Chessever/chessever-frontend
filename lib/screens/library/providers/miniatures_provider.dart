import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
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
  final items = orderMiniaturesByDayAndAverageRating(
    ref.watch(miniaturesPaginatedProvider).items,
  );
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
///
/// Ranking is always high player ELO from Supabase `chess_players` (same rules
/// as For You → Favorites → Players). [sort] is kept for filter-dialog chrome
/// compatibility but does not change the data source.
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
    this.items = const <PlayerStandingModel>[],
    this.totalCount = 0,
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  final List<PlayerStandingModel> items;
  final int totalCount;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  MiniaturePlayersState copyWith({
    List<PlayerStandingModel>? items,
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

/// Maps a Supabase [ChessPlayer] into the card model used by Miniatures Players
/// (same standing model as Favorites → Players).
PlayerStandingModel chessPlayerToStandingModel(ChessPlayer player) {
  return PlayerStandingModel(
    name: player.name,
    countryCode: CountryUtils.toIso2Code(player.country ?? ''),
    score: player.rating ?? 0,
    scoreChange: 0,
    matchScore: null,
    title: player.title,
    fideId: player.fideid,
  );
}

/// Resolved rows survive scrolling: the row provider is autoDispose, so
/// without this a scroll back up would refire every lookup. Null values are
/// cached too — a player with no gamebase match must not be retried per frame.
final _miniaturePlayerRecordCache = <int, MiniaturePlayer?>{};

/// One shared future per player while a lookup is in flight. The list row and
/// a tap on that row both ask for the same record, so without this the same
/// name search goes out twice.
final _miniaturePlayerRecordInFlight = <int, Future<MiniaturePlayer?>>{};

/// Test hook: drops the in-memory W-L lookup cache between cases.
void clearMiniaturePlayerRecordCacheForTest() {
  _miniaturePlayerRecordCache.clear();
  _miniaturePlayerRecordInFlight.clear();
}

/// True once a lookup for [fideId] has settled — including a settled miss.
/// A row uses this to tell "no gamebase record" apart from "not looked up
/// yet", so a confirmed miss leaves the score slot empty instead of shimmering
/// forever.
bool hasResolvedMiniaturePlayerRecord(int fideId) =>
    _miniaturePlayerRecordCache.containsKey(fideId);

/// Synchronous read of an already-resolved record. Lets a row paint W-L on its
/// very first frame after a scroll back, instead of flashing a placeholder
/// while its autoDispose provider re-runs against the same cache.
MiniaturePlayer? cachedMiniaturePlayerRecord(int fideId) =>
    _miniaturePlayerRecordCache[fideId];

/// Attaches any W-L already resolved in this session onto a freshly fetched
/// page, synchronously. Nothing is fetched here: it is the "free" part of
/// enrichment, so the first paint of a revisited tab is already complete.
List<PlayerStandingModel> applyCachedMiniatureRecords(
  List<PlayerStandingModel> players,
) {
  return players.map((player) {
    final fideId = player.fideId;
    if (fideId == null || player.matchScore != null) return player;
    final record = _miniaturePlayerRecordCache[fideId];
    if (record == null) return player;
    return player.copyWith(
      matchScore: record.winLossLabel,
      gamebasePlayerId: record.playerId,
    );
  }).toList(growable: false);
}

/// Picks the gamebase leaderboard row that is provably the same person.
///
/// FIDE id is the only trustworthy key (names collide, and gamebase names come
/// from PGN headers). A row without a FIDE id is accepted only on an exact
/// name match, which is how the leaderboard was already keyed before the tab
/// moved to ELO ranking.
MiniaturePlayer? matchMiniaturePlayerRecord({
  required List<MiniaturePlayer> candidates,
  required int fideId,
  required String name,
}) {
  MiniaturePlayer? byName;
  final wanted = name.trim().toLowerCase();
  for (final candidate in candidates) {
    if (candidate.fideId == fideId) return candidate;
    if (candidate.fideId == null &&
        byName == null &&
        candidate.name.trim().toLowerCase() == wanted) {
      byName = candidate;
    }
  }
  return byName;
}

/// Resolves the gamebase miniature row for one high-ELO card (W-L + playerId).
///
/// Full name first, then surname as a fallback for accent/format drift between
/// Supabase and gamebase name sources. Results (including null misses) are
/// cached by FIDE id so the list and scorecard share one lookup.
Future<MiniaturePlayer?> resolveMiniaturePlayerRecord({
  required GamebaseRepository repo,
  required int fideId,
  required String name,
}) {
  if (_miniaturePlayerRecordCache.containsKey(fideId)) {
    return Future.value(_miniaturePlayerRecordCache[fideId]);
  }
  // Join an in-flight lookup rather than firing a second identical search.
  final pending = _miniaturePlayerRecordInFlight[fideId];
  if (pending != null) return pending;

  final future = _lookupMiniaturePlayerRecord(
    repo: repo,
    fideId: fideId,
    name: name,
  );
  _miniaturePlayerRecordInFlight[fideId] = future;
  return future.whenComplete(
    () => _miniaturePlayerRecordInFlight.remove(fideId),
  );
}

Future<MiniaturePlayer?> _lookupMiniaturePlayerRecord({
  required GamebaseRepository repo,
  required int fideId,
  required String name,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    _miniaturePlayerRecordCache[fideId] = null;
    return null;
  }

  Future<MiniaturePlayer?> lookup(String search, int limit) async {
    final page = await repo.getMiniaturePlayers(search: search, limit: limit);
    return matchMiniaturePlayerRecord(
      candidates: page.items,
      fideId: fideId,
      name: trimmed,
    );
  }

  try {
    var record = await lookup(trimmed, 10);
    final surname = trimmed.split(',').first.trim();
    if (record == null && surname.isNotEmpty && surname != trimmed) {
      record = await lookup(surname, 30);
    }
    // Cache hits and confirmed misses only. Network errors stay uncached so
    // pull-to-refresh can retry rather than freeze empty W-L forever.
    _miniaturePlayerRecordCache[fideId] = record;
    return record;
  } catch (e, st) {
    // Decoration only — a failed lookup leaves the score slot empty instead
    // of surfacing an error over an otherwise good list.
    talker.handle(e, st);
    return null;
  }
}

/// The gamebase leaderboard row behind one ELO-ranked card, resolved lazily by
/// the row that is actually on screen (see [cachedMiniaturePlayerRecord] for
/// the synchronous side). Also the scorecard source for a tap.
///
/// Deliberately per-row: the page used to block its own first paint on a
/// `Future.wait` over every row's name search, so the whole list sat under
/// shimmer until the slowest of ~20 gamebase lookups landed.
final miniaturePlayerRecordProvider = FutureProvider.autoDispose
    .family<MiniaturePlayer?, ({int fideId, String name})>((ref, key) async {
      return resolveMiniaturePlayerRecord(
        repo: ref.read(gamebaseRepositoryProvider),
        fideId: key.fideId,
        name: key.name,
      );
    });

/// Pure merge of a paginated high-ELO page into list state (append + hasMore).
///
/// Exposed for unit tests so pagination can be verified without Supabase/UI.
MiniaturePlayersState mergeMiniaturePlayersPage({
  required MiniaturePlayersState previous,
  required List<PlayerStandingModel> page,
  required bool reset,
  required int pageSize,
  int? totalCount,
}) {
  final items =
      reset
          ? List<PlayerStandingModel>.from(page)
          : <PlayerStandingModel>[...previous.items, ...page];
  return previous.copyWith(
    items: items,
    totalCount: totalCount ?? items.length,
    isLoading: false,
    hasMore: page.length >= pageSize,
    error: null,
  );
}

/// Offset-paginated high-ELO player leaderboard (Supabase `chess_players`).
/// Recreated whenever the query changes, mirroring [miniaturesPaginatedProvider].
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
  static const int pageSize = 20;

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
      final repo = _ref.read(chessPlayerRepositoryProvider);
      final titles =
          _query.titles.isEmpty
              ? null
              : _query.titles.map((t) => t.apiValue);
      final search = (_query.search ?? '').trim();

      final players = await retryTransientRead(
        () =>
            search.isEmpty
                ? repo.getTopPlayers(
                  limit: pageSize,
                  offset: offset,
                  titles: titles,
                )
                : repo.searchAllPlayers(
                  query: search,
                  limit: pageSize,
                  offset: offset,
                  titles: titles,
                ),
      );
      if (!mounted || seq != _requestSeq) return;

      // Paint as soon as the ranking page is in. W-L is decoration supplied by
      // gamebase, one name search per row, so waiting for it here used to keep
      // the whole list under shimmer for the slowest lookup of the page. Rows
      // resolve their own record once they are on screen; anything already
      // resolved this session rides along on this first frame.
      final standings = players.map(chessPlayerToStandingModel).toList();
      final page = applyCachedMiniatureRecords(standings);

      state = mergeMiniaturePlayersPage(
        previous: state,
        page: page,
        reset: reset,
        pageSize: pageSize,
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
      final items = orderMiniaturesByDayAndAverageRating(
        ref.watch(miniaturePlayerGamesPaginatedProvider(playerId)).items,
      );
      return items
          .map((item) => item.toGamesTourModel())
          .toList(growable: false);
    });
