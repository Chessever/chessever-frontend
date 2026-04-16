import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
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

  /// Get filtered games based on current filter settings
  /// Combines search results with filter settings (AND logic)
  List<GamesTourModel> get filteredGames {
    if (!filter.hasActiveFilters) return games;
    // Pass searchQuery for Color filter to work correctly
    return GameFilterHelper.applyFilter(
      games,
      filter,
      playerNameQuery: searchQuery,
    );
  }

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
    try {
      final countryState = _ref.read(effectiveCountryProvider);
      final country = countryState.valueOrNull;

      if (country == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Please select a country first',
        );
        return;
      }

      final countryCode = country.countryCode;
      final countryName = country.name;

      debugPrint('[CountrymenGames] Initial load: $countryName ($countryCode)');

      state = state.copyWith(
        countryCode: countryCode,
        countryName: countryName,
      );

      // Reset pagination trackers
      _availableDates = [];
      _hasMoreDates = true;

      await _fetchNextDates(isInitial: true);
    } catch (e) {
      debugPrint('[CountrymenGames] Initial load error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchNextDates(isInitial: false);
  }

  Future<void> refreshGames() async {
    // Reset everything
    _availableDates = [];
    _hasMoreDates = true;
    _currentSearchQuery = '';

    state = CountrymenCombinedGamesState(
      isLoading: true,
      countryCode: state.countryCode,
      countryName: state.countryName,
    );

    // Re-read country in case it changed
    final countryState = _ref.read(effectiveCountryProvider);
    final country = countryState.valueOrNull;

    if (country != null) {
      state = state.copyWith(
        countryCode: country.countryCode,
        countryName: country.name,
      );
    }

    await _fetchNextDates(isInitial: true);
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

    await _fetchSearchResults(isInitial: true);
  }

  /// Clear search and go back to normal listing
  Future<void> clearSearch() async {
    if (_currentSearchQuery.isEmpty && !state.isSearching) return;

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

    await _fetchNextDates(isInitial: true);
  }

  /// Fetch search results from Supabase
  /// Uses large batch sizes to ensure all matching games can be displayed
  static const int _searchBatchSize = 500;

  Future<void> _fetchSearchResults({required bool isInitial}) async {
    if (!mounted) return;

    final countryCode = state.countryCode;
    final query = _currentSearchQuery;

    if (countryCode == null || countryCode.isEmpty || query.isEmpty) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      debugPrint(
        '[CountrymenSearch] Searching for "$query" in country $fideCode',
      );

      final games = await gameRepo.searchCountrymenGames(
        countryCode: fideCode,
        query: query,
        limit: _searchBatchSize,
        offset: isInitial ? 0 : state.games.length,
      );

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

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: games.length >= _searchBatchSize,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[CountrymenSearch] Error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load more search results (for pagination)
  Future<void> loadMoreSearchResults() async {
    if (state.isLoading || !state.hasMore || !state.isSearching) return;
    state = state.copyWith(isLoading: true);
    await _fetchSearchResults(isInitial: false);
  }

  /// Main method: Fetch next batch of dates and their games
  Future<void> _fetchNextDates({required bool isInitial}) async {
    if (!mounted) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final countryCode = state.countryCode;

      if (countryCode == null || countryCode.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          hasMore: false,
          error: 'No country selected',
        );
        return;
      }

      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      // Step 1: Get available dates if not cached
      if (_availableDates.isEmpty && _hasMoreDates) {
        final dates = await gameRepo.getDistinctDatesForCountry(
          countryCode: fideCode,
          limit: 30, // Get enough dates
          offset: 0,
        );
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
          final moreDates = await gameRepo.getDistinctDatesForCountry(
            countryCode: fideCode,
            limit: 30,
            offset: _availableDates.length,
          );
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
            );
            return;
          }
        }

        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      await _loadGamesForDates(
        dates: datesToLoad,
        fideCode: fideCode,
        isInitial: isInitial,
        dateOffset: dateOffset,
      );
    } catch (e) {
      debugPrint('[CountrymenGames] Fetch error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load ALL games for the specified dates
  Future<void> _loadGamesForDates({
    required List<DateTime> dates,
    required String fideCode,
    required bool isInitial,
    required int dateOffset,
  }) async {
    final gameRepo = _ref.read(gameRepositoryProvider);
    final newGames = <GamesTourModel>[];
    final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);
    final loadedDates = List<DateTime>.from(isInitial ? [] : state.loadedDates);

    for (final date in dates) {
      debugPrint(
        '[CountrymenGames] Loading ALL games for ${date.toString().split(' ')[0]}',
      );

      final dayGames = await gameRepo.getGamesByCountryAndDate(
        countryCode: fideCode,
        date: date,
        eco: state.filter.eco.isAll ? null : state.filter.eco.code,
      );

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

    if (!mounted) return;

    state = state.copyWith(
      games: allGames,
      isLoading: false,
      hasMore: hasMore,
      seenGameIds: seenKeys,
      loadedDates: loadedDates,
      dateOffset: newDateOffset,
    );
  }

  /// Generate a dedupe key based on game content, not IDs.
  /// Uses: sorted player names + date + result
  String _generateDedupeKey(GamesTourModel game) {
    // Normalize player names: lowercase, trim, remove extra spaces
    final white = _normalizePlayerName(game.whitePlayer.name);
    final black = _normalizePlayerName(game.blackPlayer.name);

    // Sort players alphabetically so Carlsen|Caruana == Caruana|Carlsen
    // This handles reversed board orientation between sources
    final players = [white, black]..sort();

    // Use date if available
    final date =
        game.lastMoveTime != null
            ? '${game.lastMoveTime!.year}-${game.lastMoveTime!.month.toString().padLeft(2, '0')}-${game.lastMoveTime!.day.toString().padLeft(2, '0')}'
            : 'unknown';

    final result = game.gameStatus.displayText;

    return '${players[0]}|${players[1]}|$date|$result';
  }

  /// Normalize player name for deduplication.
  /// Handles variations like "Carlsen, Magnus" vs "Magnus Carlsen"
  String _normalizePlayerName(String name) {
    // Lowercase and trim
    var normalized = name.toLowerCase().trim();

    // Remove extra whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');

    // If name contains comma (e.g., "Carlsen, Magnus"), normalize to "magnus carlsen"
    if (normalized.contains(',')) {
      final parts = normalized.split(',').map((p) => p.trim()).toList();
      if (parts.length == 2) {
        // Swap order: "Last, First" -> "first last"
        normalized = '${parts[1]} ${parts[0]}';
      }
    }

    return normalized;
  }

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
    return _formatDateKey(date);
  }

  String _formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Apply a new filter to the games
  void applyFilter(GameFilter filter) {
    debugPrint(
      '[CountrymenGames] Applying filter: result=${filter.result}, color=${filter.color}, timeControl=${filter.timeControl}, eco=${filter.eco.code}',
    );
    final ecoChanged = filter.eco != state.filter.eco;
    state = state.copyWith(filter: filter);

    // ECO filter is applied server-side, so we need to refetch
    if (ecoChanged) {
      _availableDates = [];
      _hasMoreDates = true;
      state = state.copyWith(
        games: [],
        seenGameIds: {},
        loadedDates: [],
        dateOffset: 0,
        hasMore: true,
        isLoading: true,
      );
      _fetchNextDates(isInitial: true);
    }
  }

  /// Clear all filters
  void clearFilter() {
    debugPrint('[CountrymenGames] Clearing filter');
    state = state.copyWith(filter: GameFilter.defaultFilter());
  }
}
