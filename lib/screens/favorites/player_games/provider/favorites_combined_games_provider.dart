import 'dart:async';
import 'package:chessever2/providers/game_list_live_first_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class FavoritesCombinedGamesState {
  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final Set<String> seenGameIds;

  /// The query the listed [games] answer: '' for the plain list. It changes
  /// when a search's games land, not at the keystroke, so the list on screen
  /// and everything drawn from it (sections, the empty state) always agree.
  final String searchQuery;
  final Set<String> selectedFideIds;
  final GameFilter filter;
  final int dateOffset; // For date-based pagination

  /// A fetch that replaces the whole list (a search, its close, a filter, a
  /// refresh) is on its way while the list it replaces stays on screen: no
  /// spinner wipe, a quiet progress line instead. Ends with [isLoading].
  final bool isReplacing;

  FavoritesCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.seenGameIds = const {},
    this.searchQuery = '',
    this.selectedFideIds = const {},
    GameFilter? filter,
    this.dateOffset = 0,
    this.isReplacing = false,
  }) : filter = filter ?? GameFilter();

  bool get isSearching => searchQuery.isNotEmpty;
  bool get isFiltering => selectedFideIds.isNotEmpty;

  // Favorites queries apply the complete search/filter/player-selection
  // intersection in Supabase. Applying the filter again here can reject valid
  // server results because a text query is not necessarily a player name.
  List<GamesTourModel> get filteredGames => games;

  FavoritesCombinedGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    String? error,
    Set<String>? seenGameIds,
    String? searchQuery,
    Set<String>? selectedFideIds,
    GameFilter? filter,
    int? dateOffset,
    bool? isReplacing,
  }) {
    return FavoritesCombinedGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      seenGameIds: seenGameIds ?? this.seenGameIds,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedFideIds: selectedFideIds ?? this.selectedFideIds,
      filter: filter ?? this.filter,
      dateOffset: dateOffset ?? this.dateOffset,
      // A load that ends ends the replacement with it.
      isReplacing:
          isReplacing ?? (isLoading == false ? false : this.isReplacing),
    );
  }
}

/// The plain list as it stood when a search began, put back as the search
/// closes so the list returns exactly as it was left, with no fetch.
class _ListBeforeSearch {
  _ListBeforeSearch(this.state, this.availableDates, this.hasMoreDates);

  final FavoritesCombinedGamesState state;
  final List<DateTime> availableDates;
  final bool hasMoreDates;
}

// --- Provider ---

final favoritesCombinedGamesProvider =
    StateNotifierProvider.autoDispose<
      FavoritesCombinedGamesNotifier,
      FavoritesCombinedGamesState
    >((ref) => FavoritesCombinedGamesNotifier(ref));

class FavoritesCombinedGamesNotifier
    extends StateNotifier<FavoritesCombinedGamesState> {
  final Ref _ref;
  static const int _datesPerBatch = 3; // Load 3 days at a time

  // Cache available dates
  List<DateTime> _availableDates = [];
  bool _hasMoreDates = true;
  int _requestGeneration = 0;

  /// The query being fetched or listed. [FavoritesCombinedGamesState
  /// .searchQuery] follows it once its games land.
  String _currentSearchQuery = '';

  /// The plain list the running search replaced, for [clearSearch].
  _ListBeforeSearch? _beforeSearch;

  /// A failed replacement keeps the list it was replacing (a background
  /// refresh) instead of showing the error.
  bool _keepListOnError = false;

  /// Game ids [ensureListed] is fetching, so a second call for the same
  /// live set does not fetch them again.
  final Set<String> _listing = <String>{};

  int _beginRequest() => ++_requestGeneration;

  bool _isCurrentRequest(int generation) =>
      mounted && generation == _requestGeneration;

  FavoritesCombinedGamesNotifier(this._ref)
    : super(FavoritesCombinedGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    final requestGeneration = _beginRequest();
    try {
      _availableDates = [];
      _hasMoreDates = true;
      await _fetchNextDates(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    } catch (e) {
      debugPrint('[FavoritesGames] Initial load error: $e');
      if (!_isCurrentRequest(requestGeneration)) return;
      state = state.copyWith(
        isLoading: false,
        error: userFacingError(
          e,
          fallback: 'Could not load games. Please try again.',
        ),
      );
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchNextDates(
      isInitial: false,
      requestGeneration: _requestGeneration,
    );
  }

  /// Starts a fetch that replaces the whole list ([next] is the state it
  /// starts from). The list on screen stays until the new one lands, and is
  /// marked as being replaced when it is an answer (games, or none). A
  /// first load still on its way, an error, or a list [next] clears has
  /// nothing to keep: the fetch is a first load, with its spinner.
  int _beginReplacement(
    FavoritesCombinedGamesState next, {
    bool keepListOnError = false,
  }) {
    final requestGeneration = _beginRequest();
    _availableDates = [];
    _hasMoreDates = true;
    _keepListOnError = keepListOnError;
    final answerOnScreen =
        next.games.isNotEmpty ||
        (state.games.isEmpty &&
            state.error == null &&
            (!state.isLoading || state.isReplacing));
    state = next.copyWith(
      isLoading: true,
      isReplacing: answerOnScreen,
      error: null,
    );
    return requestGeneration;
  }

  /// Fetches the first page for [_currentSearchQuery]: the search's games,
  /// or the plain list when nothing is searched.
  Future<void> _fetchReplacement(int requestGeneration) {
    return _currentSearchQuery.isNotEmpty
        ? _fetchSearchResults(
            isInitial: true,
            requestGeneration: requestGeneration,
          )
        : _fetchNextDates(
            isInitial: true,
            requestGeneration: requestGeneration,
          );
  }

  /// Refetches the list as it is (search, filters and players kept). The
  /// list stays on screen until the fresh one lands, and stays if the fetch
  /// fails.
  Future<void> refreshGames() async {
    // A refresh is newer than the list a running search would put back.
    _beforeSearch = null;
    final favorites =
        _ref.read(favoritePlayersNotifierProvider).valueOrNull?.players ?? [];
    final availableFideIds = favorites
        .where((favorite) => favorite.fideId != null)
        .map((favorite) => favorite.fideId!.toString())
        .toSet();
    final selectedFideIds = state.selectedFideIds
        .where(availableFideIds.contains)
        .toSet();
    final requestGeneration = _beginReplacement(
      state.copyWith(selectedFideIds: selectedFideIds),
      keepListOnError: true,
    );
    await _fetchReplacement(requestGeneration);
  }

  /// Toggle a player filter by FIDE ID
  Future<void> togglePlayerFilter(String fideId) async {
    final currentFilters = Set<String>.from(state.selectedFideIds);

    if (currentFilters.contains(fideId)) {
      currentFilters.remove(fideId);
    } else {
      currentFilters.add(fideId);
    }

    final requestGeneration = _beginReplacement(
      state.copyWith(selectedFideIds: currentFilters),
    );
    await _fetchReplacement(requestGeneration);
  }

  /// Clear all player filters
  Future<void> clearPlayerFilters() async {
    if (state.selectedFideIds.isEmpty) return;

    final requestGeneration = _beginReplacement(
      state.copyWith(selectedFideIds: {}),
    );
    await _fetchReplacement(requestGeneration);
  }

  Future<void> applyFilter(GameFilter newFilter) async {
    final filterChanged = newFilter != state.filter;
    if (!filterChanged) return;

    // Every filter dimension is now applied server-side, so any change must
    // trigger a fresh refetch — local lists are incomplete. Re-run whichever
    // path is currently active (search vs date pagination) so the filter is
    // respected even when the user has an open search query.
    final requestGeneration = _beginReplacement(
      state.copyWith(filter: newFilter),
    );
    await _fetchReplacement(requestGeneration);
  }

  Future<void> clearFilter() => applyFilter(GameFilter.defaultFilter());

  /// Searches the followed players' games (players, openings, ECO codes).
  ///
  /// The list on screen stays until the hits land. The first search after
  /// the plain list keeps that list aside for [clearSearch].
  Future<void> searchGames(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return clearSearch();
    if (trimmedQuery == _currentSearchQuery && state.games.isNotEmpty) return;

    if (_currentSearchQuery.isEmpty) _beforeSearch = _listBeforeSearch();
    _currentSearchQuery = trimmedQuery;
    final requestGeneration = _beginReplacement(state);
    await _fetchSearchResults(
      isInitial: true,
      requestGeneration: requestGeneration,
    );
  }

  /// Ends the search. The plain list it replaced comes back at once, as it
  /// was left, when the filters and players are still the ones it was
  /// fetched with; otherwise it is fetched again, the hits staying on screen
  /// until it lands.
  Future<void> clearSearch() async {
    // Nothing searched, or the plain list is already on its way back.
    if (_currentSearchQuery.isEmpty &&
        (!state.isSearching || state.isReplacing)) {
      return;
    }

    final before = _beforeSearch;
    _beforeSearch = null;
    _currentSearchQuery = '';
    if (before != null &&
        before.state.filter == state.filter &&
        setEquals(before.state.selectedFideIds, state.selectedFideIds)) {
      // Any search still on its way is dropped.
      _beginRequest();
      _availableDates = List.of(before.availableDates);
      _hasMoreDates = before.hasMoreDates;
      state = before.state;
      return;
    }

    final requestGeneration = _beginReplacement(state);
    await _fetchNextDates(
      isInitial: true,
      requestGeneration: requestGeneration,
    );
  }

  /// The plain list as it stands, if it is whole enough to come back as it
  /// is: not a first load still on its way, not an error, not itself being
  /// replaced. A page still loading is let go (the search drops it) and is
  /// fetched again from the bottom of the list.
  _ListBeforeSearch? _listBeforeSearch() {
    final current = state;
    if (current.isSearching || current.isReplacing || current.error != null) {
      return null;
    }
    if (current.isLoading && current.games.isEmpty) return null;
    return _ListBeforeSearch(
      current.copyWith(isLoading: false),
      List.of(_availableDates),
      _hasMoreDates,
    );
  }

  /// Nothing (more) to list for [query]. A first page replaces whatever the
  /// list still shows with nothing; a later page just ends the list.
  void _landNothing(
    int requestGeneration, {
    required bool isInitial,
    required String query,
  }) {
    if (!_isCurrentRequest(requestGeneration)) return;
    state = isInitial
        ? state.copyWith(
            games: const [],
            seenGameIds: const {},
            dateOffset: 0,
            searchQuery: query,
            isLoading: false,
            hasMore: false,
          )
        : state.copyWith(isLoading: false, hasMore: false);
  }

  /// A fetch failed. A first page that replaced a search or a filter shows
  /// the error (Retry runs it again); a refresh keeps the list it had, and a
  /// later page keeps what is listed.
  void _fail(
    Object error,
    int requestGeneration, {
    required bool isInitial,
    required String query,
  }) {
    if (!_isCurrentRequest(requestGeneration)) return;
    final message = userFacingError(
      error,
      fallback: 'Could not load games. Please try again.',
    );
    if (isInitial && !_keepListOnError) {
      state = state.copyWith(
        games: const [],
        seenGameIds: const {},
        dateOffset: 0,
        searchQuery: query,
        isLoading: false,
        hasMore: false,
        error: message,
      );
      return;
    }
    state = state.copyWith(
      isLoading: false,
      error: state.games.isEmpty ? message : null,
    );
  }

  /// Fetch search results
  /// Uses large batch sizes to ensure all matching games can be displayed
  static const int _searchBatchSize = 500;

  Future<void> _fetchSearchResults({
    required bool isInitial,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(requestGeneration)) return;

    final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
    final favorites = favoritesAsync.valueOrNull?.players ?? [];
    final query = _currentSearchQuery;

    if (favorites.isEmpty || query.isEmpty) {
      _landNothing(requestGeneration, isInitial: isInitial, query: query);
      return;
    }

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      var fideIds = favorites
          .where((f) => f.fideId != null)
          .map((f) => f.fideId!.toString())
          .toList();
      if (state.selectedFideIds.isNotEmpty) {
        fideIds = fideIds.where(state.selectedFideIds.contains).toList();
      }

      if (fideIds.isEmpty) {
        _landNothing(requestGeneration, isInitial: isInitial, query: query);
        return;
      }

      final games = await retryTransientRead(
        () => gameRepo.searchFavoritesGames(
          fideIds: fideIds,
          playerNames: [],
          query: query,
          filter: state.filter,
          limit: _searchBatchSize,
          offset: isInitial ? 0 : state.games.length,
        ),
      );

      if (!_isCurrentRequest(requestGeneration)) return;

      final newGames = <GamesTourModel>[];
      final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);

      for (final game in games) {
        final gameModel = GamesTourModel.fromGame(game);
        final key = _generateDedupeKey(gameModel);
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          newGames.add(gameModel);
        }
      }

      newGames.sort(_compareByDateDesc);
      final allGames = isInitial ? newGames : [...state.games, ...newGames];

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: games.length >= _searchBatchSize,
        seenGameIds: seenKeys,
        searchQuery: query,
        dateOffset: isInitial ? 0 : null,
      );
    } catch (e) {
      debugPrint('[FavoritesSearch] Error: $e');
      _fail(e, requestGeneration, isInitial: isInitial, query: query);
    }
  }

  Future<void> loadMoreSearchResults() async {
    if (state.isLoading || !state.hasMore || !state.isSearching) return;
    state = state.copyWith(isLoading: true);
    await _fetchSearchResults(
      isInitial: false,
      requestGeneration: _requestGeneration,
    );
  }

  /// Main method: Fetch games based on current filter state
  /// - Single player filter: Fetch ALL games directly (guaranteed complete)
  /// - Multiple players or no filter: Use date-based pagination
  Future<void> _fetchNextDates({
    required bool isInitial,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(requestGeneration)) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
      final favorites = favoritesAsync.valueOrNull?.players ?? [];

      if (favorites.isEmpty) {
        _landNothing(requestGeneration, isInitial: isInitial, query: '');
        return;
      }

      // Get FIDE IDs (convert int? to String)
      var fideIds = favorites
          .where((f) => f.fideId != null)
          .map((f) => f.fideId!.toString())
          .toList();

      // Apply filter if selected
      final selectedFilters = state.selectedFideIds;
      if (selectedFilters.isNotEmpty) {
        fideIds = fideIds.where((id) => selectedFilters.contains(id)).toList();
      }

      if (fideIds.isEmpty) {
        _landNothing(requestGeneration, isInitial: isInitial, query: '');
        return;
      }

      final gameRepo = _ref.read(gameRepositoryProvider);

      // Get available dates if not cached (day-based pagination)
      if (_availableDates.isEmpty && _hasMoreDates) {
        final dates = await retryTransientRead(
          () => gameRepo.getDistinctDatesForFavorites(
            fideIds: fideIds,
            filter: state.filter,
            limit: 30,
            offset: 0,
          ),
        );
        if (!_isCurrentRequest(requestGeneration)) return;
        _availableDates = dates;
        _hasMoreDates = dates.length >= 30;
        debugPrint('[FavoritesGames] Got ${dates.length} available dates');
      }

      // Determine which dates to load
      final dateOffset = isInitial ? 0 : state.dateOffset;
      final datesToLoad = _availableDates
          .skip(dateOffset)
          .take(_datesPerBatch)
          .toList();

      if (datesToLoad.isEmpty) {
        // Try to get more dates
        if (_hasMoreDates) {
          final moreDates = await retryTransientRead(
            () => gameRepo.getDistinctDatesForFavorites(
              fideIds: fideIds,
              filter: state.filter,
              limit: 30,
              offset: _availableDates.length,
            ),
          );
          if (!_isCurrentRequest(requestGeneration)) return;
          _availableDates.addAll(moreDates);
          _hasMoreDates = moreDates.length >= 30;

          final retryDates = _availableDates
              .skip(dateOffset)
              .take(_datesPerBatch)
              .toList();

          if (retryDates.isNotEmpty) {
            await _loadGamesForDates(
              dates: retryDates,
              fideIds: fideIds,
              isInitial: isInitial,
              dateOffset: dateOffset,
              requestGeneration: requestGeneration,
            );
            return;
          }
        }

        _landNothing(requestGeneration, isInitial: isInitial, query: '');
        return;
      }

      await _loadGamesForDates(
        dates: datesToLoad,
        fideIds: fideIds,
        isInitial: isInitial,
        dateOffset: dateOffset,
        requestGeneration: requestGeneration,
      );
    } catch (e) {
      debugPrint('[FavoritesGames] Fetch error: $e');
      _fail(e, requestGeneration, isInitial: isInitial, query: '');
    }
  }

  /// Load ALL games for the specified dates
  Future<void> _loadGamesForDates({
    required List<DateTime> dates,
    required List<String> fideIds,
    required bool isInitial,
    required int dateOffset,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(requestGeneration)) return;
    final gameRepo = _ref.read(gameRepositoryProvider);
    final newGames = <GamesTourModel>[];
    final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);

    for (final date in dates) {
      debugPrint(
        '[FavoritesGames] Loading ALL games for ${date.toString().split(' ')[0]}',
      );

      final dayGames = await retryTransientRead(
        () => gameRepo.getGamesByFideIdsAndDate(
          fideIds: fideIds,
          date: date,
          filter: state.filter,
        ),
      );
      if (!_isCurrentRequest(requestGeneration)) return;

      debugPrint(
        '[FavoritesGames] Got ${dayGames.length} games for ${date.toString().split(' ')[0]}',
      );

      for (final game in dayGames) {
        final gameModel = GamesTourModel.fromGame(game);
        final key = _generateDedupeKey(gameModel);
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          newGames.add(gameModel);
        }
      }
    }

    newGames.sort(_compareByDateDesc);

    if (!_isCurrentRequest(requestGeneration)) return;

    // A later page lands after the list may have gained games meanwhile
    // ([ensureListed]): those stay where they are, never listed twice.
    final listedNow = isInitial ? const <String>{} : state.seenGameIds;
    final allGames = isInitial
        ? newGames
        : [
            ...state.games,
            for (final game in newGames)
              if (!listedNow.contains(game.gameId)) game,
          ];
    seenKeys.addAll(listedNow);
    final newDateOffset = dateOffset + dates.length;
    final hasMore = newDateOffset < _availableDates.length || _hasMoreDates;

    debugPrint(
      '[FavoritesGames] Total games: ${allGames.length}, hasMore: $hasMore',
    );

    state = state.copyWith(
      games: allGames,
      isLoading: false,
      hasMore: hasMore,
      seenGameIds: seenKeys,
      dateOffset: newDateOffset,
      // The plain list's days: no search behind them.
      searchQuery: '',
    );
  }

  /// Lists the games among [ids] the loaded days do not hold yet, so Live
  /// first lifts every game its capsule counted ([listedLiveGameIds]): a
  /// game that started after the list loaded, or one filed under a day the
  /// loaded pages do not reach. Each is merged in the list's own order
  /// (normally today, at the top); nothing already listed moves.
  ///
  /// Not while a search's hits are listed, nor while the list is being
  /// replaced or first loaded: the list that lands is ensured again by the
  /// page. A list that loaded with nothing in it (the game started after
  /// it loaded, or the filter is narrow) is listed into like any other, so
  /// the capsule over its empty state lifts what it counts. A failure
  /// leaves the list as it is.
  Future<void> ensureListed(Iterable<String> ids) async {
    final current = state;
    if (_currentSearchQuery.isNotEmpty ||
        current.isSearching ||
        current.isReplacing ||
        (current.isLoading && current.games.isEmpty)) {
      return;
    }
    final missing = <String>[
      for (final id in ids.toSet())
        if (id.isNotEmpty &&
            !current.seenGameIds.contains(id) &&
            !_listing.contains(id))
          id,
    ];
    if (missing.isEmpty) return;
    final requestGeneration = _requestGeneration;
    _listing.addAll(missing);
    try {
      final rows = await _ref
          .read(gameRepositoryProvider)
          .getGamesByIds(missing);
      if (!_isCurrentRequest(requestGeneration) ||
          _currentSearchQuery.isNotEmpty ||
          state.isSearching ||
          state.isReplacing) {
        return;
      }
      final seen = Set<String>.of(state.seenGameIds);
      final added = <GamesTourModel>[];
      for (final row in rows) {
        final GamesTourModel model;
        try {
          model = GamesTourModel.fromGame(row);
        } catch (_) {
          // A board without two named players cannot be drawn.
          continue;
        }
        if (seen.add(_generateDedupeKey(model))) added.add(model);
      }
      if (added.isEmpty) return;
      added.sort(_compareByDateDesc);
      state = state.copyWith(
        games: insertGamesInOrder(state.games, added, _compareByDateDesc),
        seenGameIds: seen,
        error: state.error,
      );
    } catch (error) {
      debugPrint('[FavoritesGames] Listing live games failed: $error');
    } finally {
      _listing.removeAll(missing);
    }
  }

  /// Generate dedupe key based on game ID (unique identifier)
  /// Previously used player names + date + result, but this caused issues
  /// when games had NULL lastMoveTime - multiple games between same players
  /// with same result would get incorrectly deduplicated.
  String _generateDedupeKey(GamesTourModel game) {
    return game.gameId;
  }

  int _compareByDateDesc(GamesTourModel a, GamesTourModel b) {
    // Primary sort: by day (most recent first). Use the UI bucket date
    // (prefers stable date_start over clobberable last_move_time) so sort and
    // UI grouping agree — otherwise a sync-bumped last_move_time would pull a
    // week-old game to the top of the list.
    final aBucket = a.bucketDate ?? DateTime(1900);
    final bBucket = b.bucketDate ?? DateTime(1900);
    final aDayOnly = DateTime(aBucket.year, aBucket.month, aBucket.day);
    final bDayOnly = DateTime(bBucket.year, bBucket.month, bBucket.day);
    final dayCmp = bDayOnly.compareTo(aDayOnly);
    if (dayCmp != 0) return dayCmp;

    final aDate = a.lastMoveTime ?? DateTime(1900);
    final bDate = b.lastMoveTime ?? DateTime(1900);

    // Secondary sort: by event average ELO (highest first)
    // This groups games from stronger events together on top
    final aAvgElo = a.avgElo ?? 0;
    final bAvgElo = b.avgElo ?? 0;
    if (aAvgElo != bAvgElo) return bAvgElo.compareTo(aAvgElo);

    // Tertiary sort: by board number (lowest first, Board 1 ahead of Board 8)
    // NULL board numbers go to the end of the event group
    final aBoard = a.boardNr ?? 999;
    final bBoard = b.boardNr ?? 999;
    if (aBoard != bBoard) return aBoard.compareTo(bBoard);

    // Quaternary sort: by exact lastMoveTime (hours/minutes) within the same day
    final timeCmp = bDate.compareTo(aDate);
    if (timeCmp != 0) return timeCmp;

    // Quinary sort: by round number descending (latest round first)
    final aRound = _extractRoundNumber(a.roundSlug ?? a.roundId);
    final bRound = _extractRoundNumber(b.roundSlug ?? b.roundId);
    if (aRound != bRound) return bRound.compareTo(aRound);

    // Final fallback: by max rating
    final aMaxRating = [
      a.whitePlayer.rating,
      a.blackPlayer.rating,
    ].reduce((a, b) => a > b ? a : b);
    final bMaxRating = [
      b.whitePlayer.rating,
      b.blackPlayer.rating,
    ].reduce((a, b) => a > b ? a : b);
    return bMaxRating.compareTo(aMaxRating);
  }

  /// Extracts round number from round slug/id (e.g., "round-11" -> 11, "round7" -> 7)
  int _extractRoundNumber(String roundSlugOrId) {
    final match = RegExp(
      r'round[-_]?(\d+)',
      caseSensitive: false,
    ).firstMatch(roundSlugOrId);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }
}
