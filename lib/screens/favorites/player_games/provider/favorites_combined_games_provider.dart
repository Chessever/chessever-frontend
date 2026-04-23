import 'dart:async';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
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
  final String searchQuery;
  final Set<String> selectedFideIds;
  final GameFilter filter;
  final int dateOffset; // For date-based pagination

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
  }) : filter = filter ?? GameFilter();

  bool get isSearching => searchQuery.isNotEmpty;
  bool get isFiltering => selectedFideIds.isNotEmpty;

  List<GamesTourModel> get filteredGames {
    if (!filter.hasActiveFilters) return games;

    int? targetFideId;
    if (selectedFideIds.length == 1) {
      targetFideId = int.tryParse(selectedFideIds.first);
    }

    return GameFilterHelper.applyFilter(
      games,
      filter,
      playerNameQuery: searchQuery,
      targetFideId: targetFideId,
    );
  }

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
    );
  }
}

// --- Provider ---

final favoritesCombinedGamesProvider = StateNotifierProvider.autoDispose<
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

  FavoritesCombinedGamesNotifier(this._ref)
    : super(FavoritesCombinedGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    try {
      _availableDates = [];
      _hasMoreDates = true;
      await _fetchNextDates(isInitial: true);
    } catch (e) {
      debugPrint('[FavoritesGames] Initial load error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchNextDates(isInitial: false);
  }

  Future<void> refreshGames() async {
    _availableDates = [];
    _hasMoreDates = true;
    _currentSearchQuery = '';

    final currentFilters = state.selectedFideIds;
    state = FavoritesCombinedGamesState(
      isLoading: true,
      selectedFideIds: currentFilters,
    );
    await _fetchNextDates(isInitial: true);
  }

  /// Toggle a player filter by FIDE ID
  Future<void> togglePlayerFilter(String fideId) async {
    final currentFilters = Set<String>.from(state.selectedFideIds);

    if (currentFilters.contains(fideId)) {
      currentFilters.remove(fideId);
    } else {
      currentFilters.add(fideId);
    }

    _availableDates = [];
    _hasMoreDates = true;
    _currentSearchQuery = '';

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      dateOffset: 0,
      hasMore: true,
      searchQuery: '',
      selectedFideIds: currentFilters,
      error: null,
    );

    await _fetchNextDates(isInitial: true);
  }

  /// Clear all player filters
  Future<void> clearPlayerFilters() async {
    if (state.selectedFideIds.isEmpty) return;

    _availableDates = [];
    _hasMoreDates = true;
    _currentSearchQuery = '';

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      dateOffset: 0,
      hasMore: true,
      searchQuery: '',
      selectedFideIds: {},
      error: null,
    );

    await _fetchNextDates(isInitial: true);
  }

  String _currentSearchQuery = '';

  void updateFilter(GameFilter newFilter) {
    state = state.copyWith(filter: newFilter);
  }

  void applyFilter(GameFilter newFilter) {
    final ecoChanged = newFilter.eco != state.filter.eco;
    state = state.copyWith(filter: newFilter);

    // ECO filter is applied server-side, so we need to refetch
    if (ecoChanged) {
      _availableDates = [];
      _hasMoreDates = true;
      state = state.copyWith(
        games: [],
        seenGameIds: {},
        dateOffset: 0,
        hasMore: true,
        isLoading: true,
      );
      _fetchNextDates(isInitial: true);
    }
  }

  void clearFilter() {
    state = state.copyWith(filter: GameFilter());
  }

  /// Search games by player name
  Future<void> searchGames(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery == _currentSearchQuery) return;

    _currentSearchQuery = trimmedQuery;
    _availableDates = [];
    _hasMoreDates = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      dateOffset: 0,
      hasMore: true,
      searchQuery: trimmedQuery,
      error: null,
    );

    if (trimmedQuery.isEmpty) {
      await _fetchNextDates(isInitial: true);
    } else {
      await _fetchSearchResults(isInitial: true);
    }
  }

  /// Clear search
  Future<void> clearSearch() async {
    if (_currentSearchQuery.isEmpty && !state.isSearching) return;

    _currentSearchQuery = '';
    _availableDates = [];
    _hasMoreDates = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      dateOffset: 0,
      hasMore: true,
      searchQuery: '',
      error: null,
    );

    await _fetchNextDates(isInitial: true);
  }

  /// Fetch search results
  /// Uses large batch sizes to ensure all matching games can be displayed
  static const int _searchBatchSize = 500;

  Future<void> _fetchSearchResults({required bool isInitial}) async {
    if (!mounted) return;

    final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
    final favorites = favoritesAsync.valueOrNull?.players ?? [];
    final query = _currentSearchQuery;

    if (favorites.isEmpty || query.isEmpty) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideIds =
          favorites
              .where((f) => f.fideId != null)
              .map((f) => f.fideId!.toString())
              .toList();

      final games = await gameRepo.searchFavoritesGames(
        fideIds: fideIds,
        playerNames: [],
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
      debugPrint('[FavoritesSearch] Error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreSearchResults() async {
    if (state.isLoading || !state.hasMore || !state.isSearching) return;
    state = state.copyWith(isLoading: true);
    await _fetchSearchResults(isInitial: false);
  }

  /// Main method: Fetch games based on current filter state
  /// - Single player filter: Fetch ALL games directly (guaranteed complete)
  /// - Multiple players or no filter: Use date-based pagination
  Future<void> _fetchNextDates({required bool isInitial}) async {
    if (!mounted) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
      final favorites = favoritesAsync.valueOrNull?.players ?? [];

      if (favorites.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false, error: null);
        return;
      }

      // Get FIDE IDs (convert int? to String)
      var fideIds =
          favorites
              .where((f) => f.fideId != null)
              .map((f) => f.fideId!.toString())
              .toList();

      // Apply filter if selected
      final selectedFilters = state.selectedFideIds;
      if (selectedFilters.isNotEmpty) {
        fideIds = fideIds.where((id) => selectedFilters.contains(id)).toList();
      }

      if (fideIds.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      final gameRepo = _ref.read(gameRepositoryProvider);

      // Get available dates if not cached (day-based pagination)
      if (_availableDates.isEmpty && _hasMoreDates) {
        final dates = await gameRepo.getDistinctDatesForFavorites(
          fideIds: fideIds,
          limit: 30,
          offset: 0,
        );
        _availableDates = dates;
        _hasMoreDates = dates.length >= 30;
        debugPrint('[FavoritesGames] Got ${dates.length} available dates');
      }

      // Determine which dates to load
      final dateOffset = isInitial ? 0 : state.dateOffset;
      final datesToLoad =
          _availableDates.skip(dateOffset).take(_datesPerBatch).toList();

      if (datesToLoad.isEmpty) {
        // Try to get more dates
        if (_hasMoreDates) {
          final moreDates = await gameRepo.getDistinctDatesForFavorites(
            fideIds: fideIds,
            limit: 30,
            offset: _availableDates.length,
          );
          _availableDates.addAll(moreDates);
          _hasMoreDates = moreDates.length >= 30;

          final retryDates =
              _availableDates.skip(dateOffset).take(_datesPerBatch).toList();

          if (retryDates.isNotEmpty) {
            await _loadGamesForDates(
              dates: retryDates,
              fideIds: fideIds,
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
        fideIds: fideIds,
        isInitial: isInitial,
        dateOffset: dateOffset,
      );
    } catch (e) {
      debugPrint('[FavoritesGames] Fetch error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load ALL games for the specified dates
  Future<void> _loadGamesForDates({
    required List<DateTime> dates,
    required List<String> fideIds,
    required bool isInitial,
    required int dateOffset,
  }) async {
    final gameRepo = _ref.read(gameRepositoryProvider);
    final newGames = <GamesTourModel>[];
    final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);

    for (final date in dates) {
      debugPrint(
        '[FavoritesGames] Loading ALL games for ${date.toString().split(' ')[0]}',
      );

      final dayGames = await gameRepo.getGamesByFideIdsAndDate(
        fideIds: fideIds,
        date: date,
        eco: state.filter.eco.isAll ? null : state.filter.eco.code,
      );

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

    final allGames = isInitial ? newGames : [...state.games, ...newGames];
    final newDateOffset = dateOffset + dates.length;
    final hasMore = newDateOffset < _availableDates.length || _hasMoreDates;

    debugPrint(
      '[FavoritesGames] Total games: ${allGames.length}, hasMore: $hasMore',
    );

    if (!mounted) return;

    state = state.copyWith(
      games: allGames,
      isLoading: false,
      hasMore: hasMore,
      seenGameIds: seenKeys,
      dateOffset: newDateOffset,
    );
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
