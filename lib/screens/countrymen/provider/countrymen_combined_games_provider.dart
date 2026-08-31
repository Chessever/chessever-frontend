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
  final String searchQuery; // Current search query
  final GameFilter filter; // Game filter settings
  final List<DateTime> loadedDates; // Dates we've fully loaded
  final int dateOffset; // For date pagination

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
    );
  }
}

// --- Provider ---

final countrymenCombinedGamesProvider = StateNotifierProvider.autoDispose<
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
        refreshGames();
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

  Future<void> refreshGames() async {
    final requestGeneration = _beginRequest();
    _availableDates = [];
    _hasMoreDates = true;
    _currentSearchQuery = state.searchQuery.trim();

    final currentFilter = state.filter;

    state = CountrymenCombinedGamesState(
      isLoading: true,
      countryCode: state.countryCode,
      countryName: state.countryName,
      searchQuery: _currentSearchQuery,
      filter: currentFilter,
    );

    // Re-read country in case it changed
    final countryState = _ref.read(effectiveCountryProvider);
    final country = countryState.valueOrNull;

    if (country != null) {
      if (!_isCurrentRequest(requestGeneration)) return;
      state = state.copyWith(
        countryCode: country.countryCode,
        countryName: country.name,
      );
    }

    if (_currentSearchQuery.isNotEmpty) {
      await _fetchSearchResults(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    } else {
      await _fetchNextDates(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    }
  }

  // Current search query for fresh queries
  String _currentSearchQuery = '';

  /// Search games with a query - queries fresh from Supabase
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

    final requestGeneration = _beginRequest();
    _currentSearchQuery = trimmedQuery;

    // Reset pagination for new search
    _availableDates = [];
    _hasMoreDates = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      loadedDates: [],
      dateOffset: 0,
      hasMore: true,
      searchQuery: trimmedQuery,
      error: null,
    );

    await _fetchSearchResults(
      isInitial: true,
      requestGeneration: requestGeneration,
    );
  }

  /// Clear search and go back to normal listing
  Future<void> clearSearch() async {
    if (_currentSearchQuery.isEmpty && !state.isSearching) return;

    final requestGeneration = _beginRequest();
    _currentSearchQuery = '';
    _availableDates = [];
    _hasMoreDates = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      loadedDates: [],
      dateOffset: 0,
      hasMore: true,
      searchQuery: '',
      error: null,
    );

    await _fetchNextDates(
      isInitial: true,
      requestGeneration: requestGeneration,
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
      if (_isCurrentRequest(requestGeneration)) {
        state = state.copyWith(isLoading: false, hasMore: false);
      }
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
      );
    } catch (e) {
      debugPrint('[CountrymenSearch] Error: $e');
      if (!_isCurrentRequest(requestGeneration)) return;
      final error = userFacingError(e, fallback: 'Failed to load games.');
      state = state.copyWith(
        isLoading: false,
        error: state.games.isEmpty ? error : null,
      );
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
        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(
            isLoading: false,
            hasMore: false,
            error: 'No country selected',
          );
        }
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
      final datesToLoad =
          _availableDates.skip(dateOffset).take(_datesPerBatch).toList();

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
          final retryDates =
              _availableDates.skip(dateOffset).take(_datesPerBatch).toList();
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

        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(isLoading: false, hasMore: false);
        }
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
      if (!_isCurrentRequest(requestGeneration)) return;
      final error = userFacingError(e, fallback: 'Failed to load games.');
      state = state.copyWith(
        isLoading: false,
        error: state.games.isEmpty ? error : null,
      );
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
    final requestGeneration = _beginRequest();
    _availableDates = [];
    _hasMoreDates = true;
    state = state.copyWith(
      filter: filter,
      games: [],
      seenGameIds: {},
      loadedDates: [],
      dateOffset: 0,
      hasMore: true,
      isLoading: true,
      error: null,
    );
    if (_currentSearchQuery.isNotEmpty) {
      await _fetchSearchResults(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    } else {
      await _fetchNextDates(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    }
  }

  /// Clear all filters
  Future<void> clearFilter() {
    debugPrint('[CountrymenGames] Clearing filter');
    return applyFilter(GameFilter.defaultFilter());
  }
}
