import 'dart:async';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class FavoritesCombinedGamesState {
  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final int supabaseOffset;
  final int gamebasePageNumber;
  final String? error;
  final Set<String> seenGameIds;
  final String searchQuery; // Current search query

  const FavoritesCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.supabaseOffset = 0,
    this.gamebasePageNumber = 1,
    this.error,
    this.seenGameIds = const {},
    this.searchQuery = '',
  });

  bool get isSearching => searchQuery.isNotEmpty;

  FavoritesCombinedGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    int? supabaseOffset,
    int? gamebasePageNumber,
    String? error,
    Set<String>? seenGameIds,
    String? searchQuery,
  }) {
    return FavoritesCombinedGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      supabaseOffset: supabaseOffset ?? this.supabaseOffset,
      gamebasePageNumber: gamebasePageNumber ?? this.gamebasePageNumber,
      error: error,
      seenGameIds: seenGameIds ?? this.seenGameIds,
      searchQuery: searchQuery ?? this.searchQuery,
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

  // Track if each source has more data
  bool _supabaseHasMore = true;
  bool _gamebaseHasMore = true;

  FavoritesCombinedGamesNotifier(this._ref)
      : super(const FavoritesCombinedGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    try {
      _supabaseHasMore = true;
      _gamebaseHasMore = true;
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
    _gamebaseHasMore = true;
    _currentSearchQuery = '';

    state = const FavoritesCombinedGamesState(isLoading: true);
    await _fetchNextBatch(isInitial: true);
  }

  // Current search query for fresh queries
  String _currentSearchQuery = '';

  /// Search games with a query - queries fresh from Supabase and Gamebase
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
    _gamebaseHasMore = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      supabaseOffset: 0,
      gamebasePageNumber: 1,
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
    _gamebaseHasMore = true;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      supabaseOffset: 0,
      gamebasePageNumber: 1,
      hasMore: true,
      searchQuery: '',
      error: null,
    );

    await _fetchNextBatch(isInitial: true);
  }

  /// Fetch search results from both sources
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
      int gamebasePageNumber = isInitial ? 1 : state.gamebasePageNumber;

      // Fetch from both sources in PARALLEL
      Future<List<GamesTourModel>>? supabaseFuture;
      Future<List<GamesTourModel>>? gamebaseFuture;

      if (_supabaseHasMore) {
        supabaseFuture = _searchSupabase(favorites, query, supabaseOffset);
      }
      if (_gamebaseHasMore) {
        gamebaseFuture = _searchGamebase(favorites, query, gamebasePageNumber);
      }

      final supabaseGames = supabaseFuture != null ? await supabaseFuture : <GamesTourModel>[];
      final gamebaseGames = gamebaseFuture != null ? await gamebaseFuture : <GamesTourModel>[];

      // Process Supabase results
      if (supabaseFuture != null) {
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

      // Process Gamebase results
      if (gamebaseFuture != null) {
        debugPrint('[FavoritesSearch] Gamebase returned ${gamebaseGames.length} games');
        if (gamebaseGames.length < _pageSize) {
          _gamebaseHasMore = false;
        }
        for (final game in gamebaseGames) {
          final key = _generateDedupeKey(game);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            newGames.add(game);
          }
        }
        gamebasePageNumber++;
      }

      // Sort by date
      newGames.sort((a, b) {
        final aDate = a.lastMoveTime ?? DateTime(1900);
        final bDate = b.lastMoveTime ?? DateTime(1900);
        return bDate.compareTo(aDate);
      });

      final allGames = isInitial ? newGames : [...state.games, ...newGames];
      final hasMore = _supabaseHasMore || _gamebaseHasMore;

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: hasMore,
        supabaseOffset: supabaseOffset,
        gamebasePageNumber: gamebasePageNumber,
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

  /// Search Gamebase for favorites games matching the query
  /// Uses player: tokens to search within favorite players' games
  Future<List<GamesTourModel>> _searchGamebase(
    List favorites,
    String query,
    int page,
  ) async {
    try {
      final gamebaseRepo = _ref.read(gamebaseRepositoryProvider);
      final games = <GamesTourModel>[];

      // Get top favorites to search (limit to avoid too many API calls)
      final topFavorites = favorites.take(5).toList();

      for (final favorite in topFavorites) {
        if (games.length >= _pageSize) break;

        try {
          final playerName = favorite.playerName as String;

          // Combine user query with player: token
          // e.g., "sicilian player:Carlsen" finds Carlsen's Sicilian games
          final fullQuery = '$query player:"$playerName"';

          debugPrint('[FavoritesSearch] Gamebase query: $fullQuery, page=$page');

          final response = await gamebaseRepo.globalSearch(
            query: fullQuery,
            resources: ['game'],
            pageNumber: page,
            pageSize: (_pageSize ~/ topFavorites.length).clamp(5, 15),
          );

          final gameResults = response.results.where((r) => r.resource == 'game');

          for (final result in gameResults) {
            if (games.length >= _pageSize) break;

            final preview = result.preview ?? const <String, dynamic>{};
            final gameUuid = preview['id']?.toString() ?? result.id;
            final game = _convertGamebaseResultToModel(gameUuid, preview);
            if (game != null) {
              games.add(game);
            }
          }

          debugPrint('[FavoritesSearch] Query for "$playerName" + "$query" returned ${gameResults.length} results');
        } catch (e) {
          debugPrint('[FavoritesSearch] Gamebase error for ${favorite.playerName}: $e');
        }
      }

      return games;
    } catch (e) {
      debugPrint('[FavoritesSearch] Gamebase error: $e');
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
      int gamebasePageNumber = isInitial ? 1 : state.gamebasePageNumber;

      // Fetch from both sources in PARALLEL for faster loading
      final futures = <Future<List<GamesTourModel>>>[];

      if (_supabaseHasMore) {
        futures.add(_fetchFromSupabase(favorites, supabaseOffset));
      }
      if (_gamebaseHasMore) {
        futures.add(_fetchFromGamebase(favorites, gamebasePageNumber));
      }

      final results = await Future.wait(futures);

      int resultIndex = 0;

      // Process Supabase results
      if (_supabaseHasMore && resultIndex < results.length) {
        final supabaseGames = results[resultIndex++];

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

      // Process Gamebase results
      if (_gamebaseHasMore && resultIndex < results.length) {
        final gamebaseGames = results[resultIndex++];

        debugPrint('[FavoritesGames] Gamebase returned ${gamebaseGames.length} games (page: $gamebasePageNumber)');

        if (gamebaseGames.length < _pageSize) {
          _gamebaseHasMore = false;
        }

        for (final game in gamebaseGames) {
          final key = _generateDedupeKey(game);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            newGames.add(game);
          }
        }

        gamebasePageNumber++;
      }

      // Sort new games by date
      newGames.sort((a, b) {
        final aDate = a.lastMoveTime ?? DateTime(1900);
        final bDate = b.lastMoveTime ?? DateTime(1900);
        return bDate.compareTo(aDate);
      });

      // Combine with existing games
      final allGames = isInitial ? newGames : [...state.games, ...newGames];

      final hasMore = _supabaseHasMore || _gamebaseHasMore;

      debugPrint('[FavoritesGames] Total games now: ${allGames.length}, hasMore: $hasMore');

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: hasMore,
        supabaseOffset: supabaseOffset,
        gamebasePageNumber: gamebasePageNumber,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[FavoritesGames] Fetch error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Generate a dedupe key based on game content, not IDs.
  /// This ensures the same game from Supabase and Gamebase is detected as duplicate.
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
      final fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId! as String)
          .toList();

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

      // Also fetch by player names for those without FIDE IDs
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

      debugPrint('[FavoritesGames] Fetched ${games.length} from Supabase');
      return games;
    } catch (e) {
      debugPrint('[FavoritesGames] Supabase fetch error: $e');
      return [];
    }
  }

  Future<List<GamesTourModel>> _fetchFromGamebase(
    List favorites,
    int page,
  ) async {
    try {
      final gamebaseRepo = _ref.read(gamebaseRepositoryProvider);
      final games = <GamesTourModel>[];

      // Limit to top 5 favorites for API efficiency
      final limitedFavorites = favorites.take(5).toList();
      if (limitedFavorites.isEmpty) return games;

      // Cycle through favorites across pages to ensure proper pagination
      // Page 1 → favorite 0, Page 2 → favorite 1, etc.
      // This ensures we don't fetch the same page for all players
      final favoriteIndex = (page - 1) % limitedFavorites.length;
      final favorite = limitedFavorites[favoriteIndex];
      final pageForThisFavorite = ((page - 1) ~/ limitedFavorites.length) + 1;

      try {
        final playerName = favorite.playerName as String;
        final query = 'player:"$playerName"';

        debugPrint('[FavoritesGames] Gamebase query: $query, page=$pageForThisFavorite (favorite #$favoriteIndex)');

        final response = await gamebaseRepo.globalSearch(
          query: query,
          resources: ['game'],
          pageNumber: pageForThisFavorite,
          pageSize: _pageSize,
        );

        final gameResults = response.results.where((r) => r.resource == 'game');

        for (final result in gameResults) {
          final preview = result.preview ?? const <String, dynamic>{};
          final gameUuid = preview['id']?.toString() ?? result.id;
          final game = _convertGamebaseResultToModel(gameUuid, preview);
          if (game != null) {
            games.add(game);
          }
        }

        debugPrint('[FavoritesGames] Query for $playerName returned ${games.length} games');
      } catch (e) {
        debugPrint('[FavoritesGames] Gamebase error for ${favorite.playerName}: $e');
      }

      return games;
    } catch (e) {
      debugPrint('[FavoritesGames] Gamebase fetch error: $e');
      return [];
    }
  }

  GamesTourModel? _convertGamebaseResultToModel(
    String id,
    Map<String, dynamic> preview,
  ) {
    try {
      final whiteName = (preview['white']?.toString() ?? 'White').trim();
      final blackName = (preview['black']?.toString() ?? 'Black').trim();
      final result = preview['result']?.toString() ?? '*';
      final event = (preview['event']?.toString() ?? 'Gamebase').trim();
      final eco = preview['eco']?.toString();
      final timeControl = preview['timeControl']?.toString();

      // Get federation info from Gamebase preview
      final whiteFed = preview['whiteFed']?.toString() ?? '';
      final blackFed = preview['blackFed']?.toString() ?? '';

      DateTime? date;
      if (preview['date'] != null) {
        date = DateTime.tryParse(preview['date'].toString());
      }

      final pgn = buildHeaderOnlyPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: result,
        event: event,
        eco: eco,
        date: date,
      );

      final whiteCard = PlayerCard(
        name: whiteName,
        federation: whiteFed,
        title: '',
        rating: int.tryParse(preview['whiteElo']?.toString() ?? '') ?? 0,
        countryCode: whiteFed.isNotEmpty ? CountryUtils.countryNameToIso2(whiteFed) : '',
        team: null,
        fideId: null,
      );

      final blackCard = PlayerCard(
        name: blackName,
        federation: blackFed,
        title: '',
        rating: int.tryParse(preview['blackElo']?.toString() ?? '') ?? 0,
        countryCode: blackFed.isNotEmpty ? CountryUtils.countryNameToIso2(blackFed) : '',
        team: null,
        fideId: null,
      );

      return GamesTourModel(
        gameId: id,
        whitePlayer: whiteCard,
        blackPlayer: blackCard,
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.fromString(result),
        roundId: 'favorites_combined',
        roundSlug: eco ?? timeControl,
        tourId: event,
        pgn: pgn,
        lastMoveTime: date,
      );
    } catch (e) {
      debugPrint('[FavoritesGames] Error converting result: $e');
      return null;
    }
  }
}
