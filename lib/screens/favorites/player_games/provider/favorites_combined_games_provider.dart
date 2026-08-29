import 'dart:async';
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
  int _requestGeneration = 0;

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

  Future<void> refreshGames() async {
    final requestGeneration = _beginRequest();
    _availableDates = [];
    _hasMoreDates = true;
    _currentSearchQuery = state.searchQuery.trim();

    final favorites =
        _ref.read(favoritePlayersNotifierProvider).valueOrNull?.players ?? [];
    final availableFideIds =
        favorites
            .where((favorite) => favorite.fideId != null)
            .map((favorite) => favorite.fideId!.toString())
            .toSet();
    final selectedFideIds =
        state.selectedFideIds.where(availableFideIds.contains).toSet();
    state = FavoritesCombinedGamesState(
      isLoading: true,
      searchQuery: _currentSearchQuery,
      selectedFideIds: selectedFideIds,
      filter: state.filter,
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

  /// Toggle a player filter by FIDE ID
  Future<void> togglePlayerFilter(String fideId) async {
    final requestGeneration = _beginRequest();
    final currentFilters = Set<String>.from(state.selectedFideIds);

    if (currentFilters.contains(fideId)) {
      currentFilters.remove(fideId);
    } else {
      currentFilters.add(fideId);
    }

    _availableDates = [];
    _hasMoreDates = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      dateOffset: 0,
      hasMore: true,
      selectedFideIds: currentFilters,
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

  /// Clear all player filters
  Future<void> clearPlayerFilters() async {
    if (state.selectedFideIds.isEmpty) return;

    final requestGeneration = _beginRequest();
    _availableDates = [];
    _hasMoreDates = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      dateOffset: 0,
      hasMore: true,
      selectedFideIds: {},
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

  String _currentSearchQuery = '';

  Future<void> applyFilter(GameFilter newFilter) async {
    final filterChanged = newFilter != state.filter;
    if (!filterChanged) return;

    // Every filter dimension is now applied server-side, so any change must
    // trigger a fresh refetch — local lists are incomplete. Re-run whichever
    // path is currently active (search vs date pagination) so the filter is
    // respected even when the user has an open search query.
    final requestGeneration = _beginRequest();
    _availableDates = [];
    _hasMoreDates = true;
    state = state.copyWith(
      filter: newFilter,
      games: [],
      seenGameIds: {},
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

  Future<void> clearFilter() => applyFilter(GameFilter.defaultFilter());

  /// Search games by player name
  Future<void> searchGames(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery == _currentSearchQuery && state.games.isNotEmpty) return;

    final requestGeneration = _beginRequest();
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
      await _fetchNextDates(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    } else {
      await _fetchSearchResults(
        isInitial: true,
        requestGeneration: requestGeneration,
      );
    }
  }

  /// Clear search
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
      if (_isCurrentRequest(requestGeneration)) {
        state = state.copyWith(isLoading: false, hasMore: false);
      }
      return;
    }

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      var fideIds =
          favorites
              .where((f) => f.fideId != null)
              .map((f) => f.fideId!.toString())
              .toList();
      if (state.selectedFideIds.isNotEmpty) {
        fideIds = fideIds.where(state.selectedFideIds.contains).toList();
      }

      if (fideIds.isEmpty) {
        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(isLoading: false, hasMore: false);
        }
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
      );
    } catch (e) {
      debugPrint('[FavoritesSearch] Error: $e');
      if (!_isCurrentRequest(requestGeneration)) return;
      final error = userFacingError(
        e,
        fallback: 'Could not load games. Please try again.',
      );
      state = state.copyWith(
        isLoading: false,
        error: state.games.isEmpty ? error : null,
      );
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
        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(isLoading: false, hasMore: false, error: null);
        }
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
        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(isLoading: false, hasMore: false);
        }
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
      final datesToLoad =
          _availableDates.skip(dateOffset).take(_datesPerBatch).toList();

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

          final retryDates =
              _availableDates.skip(dateOffset).take(_datesPerBatch).toList();

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

        if (_isCurrentRequest(requestGeneration)) {
          state = state.copyWith(isLoading: false, hasMore: false);
        }
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
      if (!_isCurrentRequest(requestGeneration)) return;
      final error = userFacingError(
        e,
        fallback: 'Could not load games. Please try again.',
      );
      state = state.copyWith(
        isLoading: false,
        error: state.games.isEmpty ? error : null,
      );
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

    final allGames = isInitial ? newGames : [...state.games, ...newGames];
    final newDateOffset = dateOffset + dates.length;
    final hasMore = newDateOffset < _availableDates.length || _hasMoreDates;

    debugPrint(
      '[FavoritesGames] Total games: ${allGames.length}, hasMore: $hasMore',
    );

    if (!_isCurrentRequest(requestGeneration)) return;

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
