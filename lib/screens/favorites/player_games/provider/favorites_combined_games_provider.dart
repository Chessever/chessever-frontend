import 'dart:async';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class FavoritesCombinedGamesState {
  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final int supabaseOffset;
  final String? error;
  final Set<String> seenGameIds;
  final String searchQuery; // Current search query
  final Set<String> selectedFideIds; // Filter chips - selected player FIDE IDs

  const FavoritesCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.supabaseOffset = 0,
    this.error,
    this.seenGameIds = const {},
    this.searchQuery = '',
    this.selectedFideIds = const {},
  });

  bool get isSearching => searchQuery.isNotEmpty;
  bool get isFiltering => selectedFideIds.isNotEmpty;

  FavoritesCombinedGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    int? supabaseOffset,
    String? error,
    Set<String>? seenGameIds,
    String? searchQuery,
    Set<String>? selectedFideIds,
  }) {
    return FavoritesCombinedGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      supabaseOffset: supabaseOffset ?? this.supabaseOffset,
      error: error,
      seenGameIds: seenGameIds ?? this.seenGameIds,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedFideIds: selectedFideIds ?? this.selectedFideIds,
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
  static const int _pageSize = 15; // Small page size for fast first render

  // Track if Supabase has more data
  bool _supabaseHasMore = true;

  FavoritesCombinedGamesNotifier(this._ref)
      : super(const FavoritesCombinedGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    try {
      _supabaseHasMore = true;
      await _fetchNextBatch(isInitial: true);
    } catch (e) {
      debugPrint('[FavoritesGames] Initial load error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchNextBatch(isInitial: false);
  }

  Future<void> refreshGames() async {
    _supabaseHasMore = true;
    _currentSearchQuery = '';

    // Preserve selected filters during refresh
    final currentFilters = state.selectedFideIds;
    state = FavoritesCombinedGamesState(
      isLoading: true,
      selectedFideIds: currentFilters,
    );
    await _fetchNextBatch(isInitial: true);
  }

  /// Toggle a player filter by FIDE ID - triggers fresh Supabase query
  Future<void> togglePlayerFilter(String fideId) async {
    final currentFilters = Set<String>.from(state.selectedFideIds);

    if (currentFilters.contains(fideId)) {
      currentFilters.remove(fideId);
    } else {
      currentFilters.add(fideId);
    }

    // Reset pagination and re-query
    _supabaseHasMore = true;
    _currentSearchQuery = '';

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      supabaseOffset: 0,
      hasMore: true,
      searchQuery: '',
      selectedFideIds: currentFilters,
      error: null,
    );

    await _fetchNextBatch(isInitial: true);
  }

  /// Clear all player filters - triggers fresh Supabase query for all favorites
  Future<void> clearPlayerFilters() async {
    if (state.selectedFideIds.isEmpty) return;

    _supabaseHasMore = true;
    _currentSearchQuery = '';

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      supabaseOffset: 0,
      hasMore: true,
      searchQuery: '',
      selectedFideIds: {},
      error: null,
    );

    await _fetchNextBatch(isInitial: true);
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
    _supabaseHasMore = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      supabaseOffset: 0,
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
    _supabaseHasMore = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      supabaseOffset: 0,
      hasMore: true,
      searchQuery: '',
      error: null,
    );

    await _fetchNextBatch(isInitial: true);
  }

  /// Fetch search results from Supabase
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
      final newGames = <GamesTourModel>[];
      final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);
      int supabaseOffset = isInitial ? 0 : state.supabaseOffset;

      if (_supabaseHasMore) {
        final supabaseGames = await _searchSupabase(favorites, query, supabaseOffset);

        debugPrint('[FavoritesSearch] Supabase returned ${supabaseGames.length} games');
        if (supabaseGames.length < _pageSize) {
          _supabaseHasMore = false;
        }
        for (final game in supabaseGames) {
          final key = _generateDedupeKey(game);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            newGames.add(game);
          }
        }
        supabaseOffset += supabaseGames.length;
      }

      // Sort by date
      newGames.sort((a, b) {
        final aDate = a.lastMoveTime ?? DateTime(1900);
        final bDate = b.lastMoveTime ?? DateTime(1900);
        return bDate.compareTo(aDate);
      });

      final allGames = isInitial ? newGames : [...state.games, ...newGames];

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: _supabaseHasMore,
        supabaseOffset: supabaseOffset,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[FavoritesSearch] Error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search Supabase for favorites games matching the query
  Future<List<GamesTourModel>> _searchSupabase(
    List favorites,
    String query,
    int offset,
  ) async {
    try {
      final gameRepo = _ref.read(gameRepositoryProvider);

      // Get FIDE IDs from favorites
      final fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId! as String)
          .toList();

      // Get player names for matching
      final playerNames = favorites
          .map((f) => f.playerName as String)
          .toList();

      debugPrint('[FavoritesSearch] Supabase search: query="$query", fideIds=${fideIds.length}, offset=$offset');

      // Use the new searchFavoritesGames method with ILIKE
      final games = await gameRepo.searchFavoritesGames(
        fideIds: fideIds,
        playerNames: playerNames,
        query: query,
        limit: _pageSize,
        offset: offset,
      );

      debugPrint('[FavoritesSearch] Supabase results: ${games.length}');

      return games.map((g) => GamesTourModel.fromGame(g)).toList();
    } catch (e) {
      debugPrint('[FavoritesSearch] Supabase error: $e');
      return [];
    }
  }

  /// Load more search results (for pagination)
  Future<void> loadMoreSearchResults() async {
    if (state.isLoading || !state.hasMore || !state.isSearching) return;
    state = state.copyWith(isLoading: true);
    await _fetchSearchResults(isInitial: false);
  }

  Future<void> _fetchNextBatch({required bool isInitial}) async {
    if (!mounted) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final favoritesAsync = _ref.read(favoritePlayersProviderNew);
      final favorites = favoritesAsync.valueOrNull ?? [];

      if (favorites.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          hasMore: false,
          error: null,
        );
        return;
      }

      final newGames = <GamesTourModel>[];
      final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);

      int supabaseOffset = isInitial ? 0 : state.supabaseOffset;

      // Fetch from Supabase
      if (_supabaseHasMore) {
        final supabaseGames = await _fetchFromSupabase(favorites, supabaseOffset);

        debugPrint('[FavoritesGames] Supabase returned ${supabaseGames.length} games (offset: $supabaseOffset)');

        if (supabaseGames.length < _pageSize) {
          _supabaseHasMore = false;
        }

        for (final game in supabaseGames) {
          final key = _generateDedupeKey(game);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            newGames.add(game);
          }
        }

        supabaseOffset += supabaseGames.length;
      }

      // Sort new games by date
      newGames.sort((a, b) {
        final aDate = a.lastMoveTime ?? DateTime(1900);
        final bDate = b.lastMoveTime ?? DateTime(1900);
        return bDate.compareTo(aDate);
      });

      // Combine with existing games
      final allGames = isInitial ? newGames : [...state.games, ...newGames];

      debugPrint('[FavoritesGames] Total games now: ${allGames.length}, hasMore: $_supabaseHasMore');

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: _supabaseHasMore,
        supabaseOffset: supabaseOffset,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[FavoritesGames] Fetch error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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
    final date = game.lastMoveTime != null
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

  Future<List<GamesTourModel>> _fetchFromSupabase(
    List favorites,
    int offset,
  ) async {
    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final games = <GamesTourModel>[];

      // Get FIDE IDs from favorites
      var fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId! as String)
          .toList();

      // If filter chips are selected, only query those specific players
      final selectedFilters = state.selectedFideIds;
      if (selectedFilters.isNotEmpty) {
        fideIds = fideIds.where((id) => selectedFilters.contains(id)).toList();
        debugPrint('[FavoritesGames] Filtering by ${fideIds.length} selected players');
      }

      if (fideIds.isNotEmpty) {
        final supabaseGames = await gameRepo.getGamesByMultipleFideIds(
          fideIds: fideIds,
          limit: _pageSize,
          offset: offset,
        );

        for (final game in supabaseGames) {
          games.add(GamesTourModel.fromGame(game));
        }
      }

      // Also fetch by player names for those without FIDE IDs (only if no filter active)
      if (selectedFilters.isEmpty) {
        final playerNames = favorites
            .where((f) => f.fideId == null || f.fideId!.isEmpty)
            .map((f) => f.playerName as String)
            .toList();

        for (final name in playerNames.take(3)) {
          try {
            final nameGames = await gameRepo.getGamesByPlayerName(
              name,
              limit: (_pageSize ~/ 3).clamp(5, 10),
              offset: offset,
            );
            for (final game in nameGames) {
              games.add(GamesTourModel.fromGame(game));
            }
          } catch (e) {
            debugPrint('[FavoritesGames] Error fetching for $name: $e');
          }
        }
      }

      debugPrint('[FavoritesGames] Fetched ${games.length} from Supabase');
      return games;
    } catch (e) {
      debugPrint('[FavoritesGames] Supabase fetch error: $e');
      return [];
    }
  }

}
