import 'dart:async';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
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

  const FavoritesCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.seenGameIds = const {},
    this.searchQuery = '',
    this.selectedFideIds = const {},
    this.filter = const GameFilter(),
    this.dateOffset = 0,
  });

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
    FavoritesCombinedGamesNotifier, FavoritesCombinedGamesState>(
  (ref) => FavoritesCombinedGamesNotifier(ref),
);

class FavoritesCombinedGamesNotifier
    extends StateNotifier<FavoritesCombinedGamesState> {
  final Ref _ref;
  static const int _datesPerBatch = 3; // Load 3 days at a time

  // Cache available dates
  List<DateTime> _availableDates = [];
  bool _hasMoreDates = true;

  FavoritesCombinedGamesNotifier(this._ref)
      : super(const FavoritesCombinedGamesState(isLoading: true)) {
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
    state = state.copyWith(filter: newFilter);
  }

  void clearFilter() {
    state = state.copyWith(filter: const GameFilter());
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
  Future<void> _fetchSearchResults({required bool isInitial}) async {
    if (!mounted) return;

    final favoritesAsync = _ref.read(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];
    final query = _currentSearchQuery;

    if (favorites.isEmpty || query.isEmpty) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId!)
          .toList();

      final games = await gameRepo.searchFavoritesGames(
        fideIds: fideIds,
        playerNames: [],
        query: query,
        limit: 50,
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
        hasMore: games.length >= 50,
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

  /// Main method: Fetch next batch of dates and ALL their games
  Future<void> _fetchNextDates({required bool isInitial}) async {
    if (!mounted) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final favoritesAsync = _ref.read(favoritePlayersProviderNew);
      final favorites = favoritesAsync.valueOrNull ?? [];

      if (favorites.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false, error: null);
        return;
      }

      // Get FIDE IDs
      var fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId!)
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

      // Get available dates if not cached
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
      final datesToLoad = _availableDates
          .skip(dateOffset)
          .take(_datesPerBatch)
          .toList();

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
      debugPrint('[FavoritesGames] Loading ALL games for ${date.toString().split(' ')[0]}');

      final dayGames = await gameRepo.getGamesByFideIdsAndDate(
        fideIds: fideIds,
        date: date,
      );

      debugPrint('[FavoritesGames] Got ${dayGames.length} games for ${date.toString().split(' ')[0]}');

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

    debugPrint('[FavoritesGames] Total games: ${allGames.length}, hasMore: $hasMore');

    if (!mounted) return;

    state = state.copyWith(
      games: allGames,
      isLoading: false,
      hasMore: hasMore,
      seenGameIds: seenKeys,
      dateOffset: newDateOffset,
    );
  }

  /// Generate dedupe key based on game content
  String _generateDedupeKey(GamesTourModel game) {
    final names = [
      _normalizeName(game.whitePlayer.name),
      _normalizeName(game.blackPlayer.name),
    ]..sort();
    final dateStr = game.lastMoveTime?.toString().split(' ')[0] ?? '';
    final result = game.gameStatus.name;
    return '${names.join('|')}|$dateStr|$result';
  }

  String _normalizeName(String name) {
    var normalized = name.toLowerCase().trim();
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    final titles = ['gm', 'im', 'fm', 'cm', 'wgm', 'wim', 'wfm', 'wcm'];
    for (final title in titles) {
      if (normalized.startsWith('$title ')) {
        normalized = normalized.substring(title.length + 1);
        break;
      }
    }
    return normalized;
  }

  int _compareByDateDesc(GamesTourModel a, GamesTourModel b) {
    final aDate = a.lastMoveTime ?? DateTime(1900);
    final bDate = b.lastMoveTime ?? DateTime(1900);
    final dateCmp = bDate.compareTo(aDate);
    if (dateCmp != 0) return dateCmp;

    // Within same date, sort by max rating
    final aMaxRating = [a.whitePlayer.rating, a.blackPlayer.rating].reduce((a, b) => a > b ? a : b);
    final bMaxRating = [b.whitePlayer.rating, b.blackPlayer.rating].reduce((a, b) => a > b ? a : b);
    return bMaxRating.compareTo(aMaxRating);
  }
}
