import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class CountrymenCombinedGamesState {
  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final Set<String> seenGameIds;
  final String? countryCode;
  final String? countryName;

  /// The query the listed [games] answer: '' for the plain list. It changes
  /// when a search's games land, not at the keystroke, so the list on screen
  /// and everything drawn from it (sections, the empty state) always agree.
  final String searchQuery;
  final GameFilter filter; // Game filter settings
  final List<DateTime> loadedDates; // Dates we've fully loaded
  final int dateOffset; // For date pagination

  /// A fetch that replaces the whole list (a search, its close, a filter, a
  /// refresh) is on its way while the list it replaces stays on screen: no
  /// spinner wipe, a quiet progress line instead. Ends with [isLoading].
  final bool isReplacing;

  CountrymenCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.seenGameIds = const {},
    this.countryCode,
    this.countryName,
    this.searchQuery = '',
    GameFilter? filter,
    this.loadedDates = const [],
    this.dateOffset = 0,
    this.isReplacing = false,
  }) : filter = filter ?? GameFilter();

  bool get isSearching => searchQuery.isNotEmpty;

  // Countrymen queries apply the complete search/filter intersection in
  // Supabase. A second local pass can treat opening text as a player name and
  // incorrectly discard valid server results.
  List<GamesTourModel> get filteredGames => games;

  CountrymenCombinedGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    String? error,
    Set<String>? seenGameIds,
    String? countryCode,
    String? countryName,
    String? searchQuery,
    GameFilter? filter,
    List<DateTime>? loadedDates,
    int? dateOffset,
    bool? isReplacing,
  }) {
    return CountrymenCombinedGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      seenGameIds: seenGameIds ?? this.seenGameIds,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      searchQuery: searchQuery ?? this.searchQuery,
      filter: filter ?? this.filter,
      loadedDates: loadedDates ?? this.loadedDates,
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

  final CountrymenCombinedGamesState state;
  final List<DateTime> availableDates;
  final bool hasMoreDates;
}

// --- Provider ---

final countrymenCombinedGamesProvider =
    StateNotifierProvider.autoDispose<
      CountrymenCombinedGamesNotifier,
      CountrymenCombinedGamesState
    >((ref) => CountrymenCombinedGamesNotifier(ref));

class CountrymenCombinedGamesNotifier
    extends StateNotifier<CountrymenCombinedGamesState> {
  final Ref _ref;
  static const int _datesPerBatch = 3; // Load 3 days at a time

  // Cache available dates
  List<DateTime> _availableDates = [];
  bool _hasMoreDates = true;
  int _requestGeneration = 0;

  /// The query being fetched or listed. [CountrymenCombinedGamesState
  /// .searchQuery] follows it once its games land.
  String _currentSearchQuery = '';

  /// The plain list the running search replaced, for [clearSearch].
  _ListBeforeSearch? _beforeSearch;

  /// A failed replacement keeps the list it was replacing (a background
  /// refresh) instead of showing the error.
  bool _keepListOnError = false;

  int _beginRequest() => ++_requestGeneration;

  bool _isCurrentRequest(int generation) =>
      mounted && generation == _requestGeneration;

  CountrymenCombinedGamesNotifier(this._ref)
    : super(CountrymenCombinedGamesState(isLoading: true)) {
    _loadInitialGames();

    // Listen for country changes (temporary or persisted)
    _ref.listen<AsyncValue<Country>>(effectiveCountryProvider, (
      previous,
      next,
    ) {
      final prevCode = previous?.valueOrNull?.countryCode;
      final nextCode = next.valueOrNull?.countryCode;
      if (prevCode != null && nextCode != null && prevCode != nextCode) {
        debugPrint('[CountrymenGames] Country changed: $prevCode -> $nextCode');
        // Another country's players: the old ones must not stand in for
        // them while the new list loads.
        refreshGames(keepList: false);
      }
    });
  }

  Future<void> _loadInitialGames() async {
    final requestGeneration = _beginRequest();
    try {
      final countryState = _ref.read(effectiveCountryProvider);
      final country = countryState.valueOrNull;

      if (country == null) {
        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(
            isLoading: false,
            error: 'Please select a country first',
          );
        }
        return;
      }

      final countryCode = country.countryCode;
      final countryName = country.name;

      debugPrint('[CountrymenGames] Initial load: $countryName ($countryCode)');

      if (!_isCurrentRequest(requestGeneration)) return;
      state = state.copyWith(
        countryCode: countryCode,
        countryName: countryName,
      );

      // Reset pagination trackers
      _availableDates = [];
      _hasMoreDates = true;

      await _fetchNextDates(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    } catch (e) {
      debugPrint('[CountrymenGames] Initial load error: $e');
      if (!_isCurrentRequest(requestGeneration)) return;
      state = state.copyWith(
        isLoading: false,
        error: userFacingError(e, fallback: 'Failed to load games.'),
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
    CountrymenCombinedGamesState next, {
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

  /// Refetches the list as it is (search and filters kept), for the country
  /// shown now. The list stays on screen until the fresh one lands, and
  /// stays if the fetch fails, unless [keepList] is false (another country:
  /// its list is cleared at once).
  Future<void> refreshGames({bool keepList = true}) async {
    // A refresh is newer than the list a running search would put back.
    _beforeSearch = null;
    final country = _ref.read(effectiveCountryProvider).valueOrNull;
    var next = state.copyWith(
      countryCode: country?.countryCode,
      countryName: country?.name,
    );
    if (!keepList) {
      next = next.copyWith(
        games: const [],
        seenGameIds: const {},
        loadedDates: const [],
        dateOffset: 0,
        hasMore: true,
      );
    }
    final requestGeneration = _beginReplacement(
      next,
      keepListOnError: keepList,
    );
    await _fetchReplacement(requestGeneration);
  }

  /// Searches the country's games (players, openings, ECO codes).
  ///
  /// The list on screen stays until the hits land. The first search after
  /// the plain list keeps that list aside for [clearSearch].
  Future<void> searchGames(String query) async {
    final trimmedQuery = query.trim();

    // If query is empty, go back to normal listing
    if (trimmedQuery.isEmpty) {
      await clearSearch();
      return;
    }

    // If same query, don't re-fetch
    if (trimmedQuery == _currentSearchQuery && state.games.isNotEmpty) {
      return;
    }

    if (_currentSearchQuery.isEmpty) _beforeSearch = _listBeforeSearch();
    _currentSearchQuery = trimmedQuery;
    final requestGeneration = _beginReplacement(state);
    await _fetchSearchResults(
      isInitial: true,
      requestGeneration: requestGeneration,
    );
  }

  /// Ends the search. The plain list it replaced comes back at once, as it
  /// was left, when the country and filters are still the ones it was
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
        before.state.countryCode == state.countryCode) {
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
    String? error,
  }) {
    if (!_isCurrentRequest(requestGeneration)) return;
    state = isInitial
        ? state.copyWith(
            games: const [],
            seenGameIds: const {},
            loadedDates: const [],
            dateOffset: 0,
            searchQuery: query,
            isLoading: false,
            hasMore: false,
            error: error,
          )
        : state.copyWith(isLoading: false, hasMore: false, error: error);
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
    final message = userFacingError(error, fallback: 'Failed to load games.');
    if (isInitial && !_keepListOnError) {
      _landNothing(
        requestGeneration,
        isInitial: true,
        query: query,
        error: message,
      );
      return;
    }
    state = state.copyWith(
      isLoading: false,
      error: state.games.isEmpty ? message : null,
    );
  }

  /// Fetch search results from Supabase
  /// Uses large batch sizes to ensure all matching games can be displayed
  static const int _searchBatchSize = 500;

  Future<void> _fetchSearchResults({
    required bool isInitial,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(requestGeneration)) return;

    final countryCode = state.countryCode;
    final query = _currentSearchQuery;

    if (countryCode == null || countryCode.isEmpty || query.isEmpty) {
      _landNothing(requestGeneration, isInitial: isInitial, query: query);
      return;
    }

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      debugPrint(
        '[CountrymenSearch] Searching for "$query" in country $fideCode',
      );

      final games = await retryTransientRead(
        () => gameRepo.searchCountrymenGames(
          countryCode: fideCode,
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
        loadedDates: isInitial ? const [] : null,
        dateOffset: isInitial ? 0 : null,
      );
    } catch (e) {
      debugPrint('[CountrymenSearch] Error: $e');
      _fail(e, requestGeneration, isInitial: isInitial, query: query);
    }
  }

  /// Load more search results (for pagination)
  Future<void> loadMoreSearchResults() async {
    if (state.isLoading || !state.hasMore || !state.isSearching) return;
    state = state.copyWith(isLoading: true);
    await _fetchSearchResults(
      isInitial: false,
      requestGeneration: _requestGeneration,
    );
  }

  /// Main method: Fetch next batch of dates and their games
  Future<void> _fetchNextDates({
    required bool isInitial,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(requestGeneration)) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final countryCode = state.countryCode;

      if (countryCode == null || countryCode.isEmpty) {
        _landNothing(
          requestGeneration,
          isInitial: isInitial,
          query: '',
          error: 'No country selected',
        );
        return;
      }

      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      // Step 1: Get available dates if not cached
      if (_availableDates.isEmpty && _hasMoreDates) {
        final dates = await retryTransientRead(
          () => gameRepo.getDistinctDatesForCountry(
            countryCode: fideCode,
            filter: state.filter,
            limit: 30, // Get enough dates
            offset: 0,
          ),
        );
        if (!_isCurrentRequest(requestGeneration)) return;
        _availableDates = dates;
        _hasMoreDates = dates.length >= 30;
        debugPrint('[CountrymenGames] Got ${dates.length} available dates');
      }

      // Step 2: Determine which dates to load
      final dateOffset = isInitial ? 0 : state.dateOffset;
      final datesToLoad = _availableDates
          .skip(dateOffset)
          .take(_datesPerBatch)
          .toList();

      if (datesToLoad.isEmpty) {
        // Try to get more dates
        if (_hasMoreDates) {
          final moreDates = await retryTransientRead(
            () => gameRepo.getDistinctDatesForCountry(
              countryCode: fideCode,
              filter: state.filter,
              limit: 30,
              offset: _availableDates.length,
            ),
          );
          if (!_isCurrentRequest(requestGeneration)) return;
          _availableDates.addAll(moreDates);
          _hasMoreDates = moreDates.length >= 30;

          // Retry with new dates
          final retryDates = _availableDates
              .skip(dateOffset)
              .take(_datesPerBatch)
              .toList();
          if (retryDates.isNotEmpty) {
            await _loadGamesForDates(
              dates: retryDates,
              fideCode: fideCode,
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
        fideCode: fideCode,
        isInitial: isInitial,
        dateOffset: dateOffset,
        requestGeneration: requestGeneration,
      );
    } catch (e) {
      debugPrint('[CountrymenGames] Fetch error: $e');
      _fail(e, requestGeneration, isInitial: isInitial, query: '');
    }
  }

  /// Load ALL games for the specified dates
  Future<void> _loadGamesForDates({
    required List<DateTime> dates,
    required String fideCode,
    required bool isInitial,
    required int dateOffset,
    required int requestGeneration,
  }) async {
    if (!_isCurrentRequest(requestGeneration)) return;
    final gameRepo = _ref.read(gameRepositoryProvider);
    final newGames = <GamesTourModel>[];
    final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);
    final loadedDates = List<DateTime>.from(isInitial ? [] : state.loadedDates);

    for (final date in dates) {
      debugPrint(
        '[CountrymenGames] Loading ALL games for ${date.toString().split(' ')[0]}',
      );

      final dayGames = await retryTransientRead(
        () => gameRepo.getGamesByCountryAndDate(
          countryCode: fideCode,
          date: date,
          filter: state.filter,
        ),
      );
      if (!_isCurrentRequest(requestGeneration)) return;

      debugPrint(
        '[CountrymenGames] Got ${dayGames.length} games for ${date.toString().split(' ')[0]}',
      );

      for (final game in dayGames) {
        final gameModel = GamesTourModel.fromGame(game);
        final key = _generateDedupeKey(gameModel);
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          newGames.add(gameModel);
        }
      }

      loadedDates.add(date);
    }

    // Sort by date descending, then by ELO
    newGames.sort(_compareByDateDesc);

    final allGames = isInitial ? newGames : [...state.games, ...newGames];
    final newDateOffset = dateOffset + dates.length;
    final hasMore = newDateOffset < _availableDates.length || _hasMoreDates;

    debugPrint(
      '[CountrymenGames] Total games: ${allGames.length}, dates loaded: ${loadedDates.length}, hasMore: $hasMore',
    );

    if (!_isCurrentRequest(requestGeneration)) return;

    state = state.copyWith(
      games: allGames,
      isLoading: false,
      hasMore: hasMore,
      seenGameIds: seenKeys,
      loadedDates: loadedDates,
      dateOffset: newDateOffset,
      // The plain list's days: no search behind them.
      searchQuery: '',
    );
  }

  /// Database game IDs are the stable identity. Content-based keys collapse
  /// legitimate rematches and multiple rounds when timestamps are null.
  String _generateDedupeKey(GamesTourModel game) => game.gameId;

  int _compareByDateDesc(GamesTourModel a, GamesTourModel b) {
    final aDayKey = _dayKeyForGame(a);
    final bDayKey = _dayKeyForGame(b);
    final dayCompare = bDayKey.compareTo(aDayKey);
    if (dayCompare != 0) {
      return dayCompare;
    }

    // Secondary sort: by event average ELO (highest first)
    final aAvgElo = a.avgElo ?? 0;
    final bAvgElo = b.avgElo ?? 0;
    if (aAvgElo != bAvgElo) return bAvgElo.compareTo(aAvgElo);

    // Tertiary sort: by board number (lowest first, Board 1 ahead of Board 8)
    final aBoard = a.boardNr ?? 999;
    final bBoard = b.boardNr ?? 999;
    if (aBoard != bBoard) return aBoard.compareTo(bBoard);

    final aTime = a.lastMoveTime ?? DateTime(1900);
    final bTime = b.lastMoveTime ?? DateTime(1900);
    final timeCompare = bTime.compareTo(aTime);
    if (timeCompare != 0) {
      return timeCompare;
    }

    return b.cardElo.compareTo(a.cardElo);
  }

  String _dayKeyForGame(GamesTourModel game) {
    final date = game.lastMoveTime;
    if (date == null) {
      return '0000-00-00';
    }
    // Local day, so the recency sort agrees with the local-day grouping/headers
    // the Games tab renders (lastMoveTime is a UTC instant).
    return _formatDateKey(date.toLocal());
  }

  String _formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Apply a new filter to the games.
  Future<void> applyFilter(GameFilter filter) async {
    debugPrint(
      '[CountrymenGames] Applying filter: result=${filter.result}, color=${filter.color}, timeControl=${filter.timeControl}, eco=${filter.eco.code}',
    );
    final filterChanged = filter != state.filter;
    if (!filterChanged) return;

    // Every filter dimension is now applied server-side, so any change must
    // trigger a fresh refetch — local lists are incomplete. Re-run whichever
    // path is currently active (search vs date pagination) so the filter is
    // respected even when the user has an open search query.
    final requestGeneration = _beginReplacement(state.copyWith(filter: filter));
    await _fetchReplacement(requestGeneration);
  }

  /// Clear all filters
  Future<void> clearFilter() {
    debugPrint('[CountrymenGames] Clearing filter');
    return applyFilter(GameFilter.defaultFilter());
  }
}
