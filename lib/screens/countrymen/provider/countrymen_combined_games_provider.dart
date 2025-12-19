import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// --- State ---

class CountrymenCombinedGamesState {
  final List<GamesTourModel> games;
  final bool isLoading;
  final bool hasMore;
  final int gamebasePageNumber;
  final String? error;
  final Set<String> seenGameIds;
  final String? countryCode;
  final String? countryName;
  final String searchQuery; // Current search query

  const CountrymenCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.gamebasePageNumber = 1,
    this.error,
    this.seenGameIds = const {},
    this.countryCode,
    this.countryName,
    this.searchQuery = '',
  });

  bool get isSearching => searchQuery.isNotEmpty;

  CountrymenCombinedGamesState copyWith({
    List<GamesTourModel>? games,
    bool? isLoading,
    bool? hasMore,
    int? gamebasePageNumber,
    String? error,
    Set<String>? seenGameIds,
    String? countryCode,
    String? countryName,
    String? searchQuery,
  }) {
    return CountrymenCombinedGamesState(
      games: games ?? this.games,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      gamebasePageNumber: gamebasePageNumber ?? this.gamebasePageNumber,
      error: error,
      seenGameIds: seenGameIds ?? this.seenGameIds,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

// --- Provider ---

final countrymenCombinedGamesProvider = StateNotifierProvider.autoDispose<
    CountrymenCombinedGamesNotifier, CountrymenCombinedGamesState>(
  (ref) => CountrymenCombinedGamesNotifier(ref),
);

class CountrymenCombinedGamesNotifier
    extends StateNotifier<CountrymenCombinedGamesState> {
  final Ref _ref;
  static const int _pageSize = 15; // Small page size for fast first render
  static const int _minElo = 2000; // Lowered to show more countrymen games

  // Track if each source has more data
  bool _supabaseHasMore = true;
  bool _gamebaseHasMore = true;

  // Track RAW offset for Supabase (how many raw games we've fetched from DB)
  // This is different from filtered games count - we need to track raw to avoid skipping games
  int _supabaseRawOffset = 0;

  // Cache the working country variation for Gamebase (once we find one that works)
  String? _workingGamebaseVariation;

  CountrymenCombinedGamesNotifier(this._ref)
      : super(const CountrymenCombinedGamesState(isLoading: true)) {
    _loadInitialGames();
  }

  Future<void> _loadInitialGames() async {
    try {
      final countryState = _ref.read(countryDropdownProvider);
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
      _supabaseHasMore = true;
      _gamebaseHasMore = true;
      _supabaseRawOffset = 0;
      _workingGamebaseVariation = null;

      await _fetchNextBatch(isInitial: true);
    } catch (e) {
      debugPrint('[CountrymenGames] Initial load error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMoreGames() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchNextBatch(isInitial: false);
  }

  Future<void> refreshGames() async {
    // Reset everything
    _supabaseHasMore = true;
    _gamebaseHasMore = true;
    _supabaseRawOffset = 0;
    _workingGamebaseVariation = null;
    _currentSearchQuery = '';

    state = CountrymenCombinedGamesState(
      isLoading: true,
      countryCode: state.countryCode,
      countryName: state.countryName,
    );

    // Re-read country in case it changed
    final countryState = _ref.read(countryDropdownProvider);
    final country = countryState.valueOrNull;

    if (country != null) {
      state = state.copyWith(
        countryCode: country.countryCode,
        countryName: country.name,
      );
    }

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
    _supabaseRawOffset = 0;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
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
    _supabaseRawOffset = 0;
    _workingGamebaseVariation = null;

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
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

    final countryCode = state.countryCode;
    final countryName = state.countryName;
    final query = _currentSearchQuery;

    if (countryCode == null || countryCode.isEmpty || query.isEmpty) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    try {
      final newGames = <GamesTourModel>[];
      final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);
      int gamebasePageNumber = isInitial ? 1 : state.gamebasePageNumber;

      // Fetch from both sources in PARALLEL
      Future<List<GamesTourModel>>? supabaseFuture;
      Future<List<GamesTourModel>>? gamebaseFuture;

      if (_supabaseHasMore) {
        supabaseFuture = _searchSupabase(countryCode, query, _supabaseRawOffset);
      }
      if (_gamebaseHasMore && countryName != null) {
        gamebaseFuture = _searchGamebase(countryName, query, gamebasePageNumber);
      }

      final supabaseGames = supabaseFuture != null ? await supabaseFuture : <GamesTourModel>[];
      final gamebaseGames = gamebaseFuture != null ? await gamebaseFuture : <GamesTourModel>[];

      // Process Supabase results
      if (supabaseFuture != null) {
        debugPrint('[CountrymenSearch] Supabase returned ${supabaseGames.length} games');
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
        _supabaseRawOffset += supabaseGames.length;
      }

      // Process Gamebase results
      if (gamebaseFuture != null) {
        debugPrint('[CountrymenSearch] Gamebase returned ${gamebaseGames.length} games');
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
        gamebasePageNumber: gamebasePageNumber,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[CountrymenSearch] Error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search Supabase for countrymen games matching the query
  Future<List<GamesTourModel>> _searchSupabase(
    String countryCode,
    String query,
    int offset,
  ) async {
    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      debugPrint('[CountrymenSearch] Supabase search: query="$query", fideCode=$fideCode, offset=$offset');

      // Use the new searchCountrymenGames method with ILIKE
      final games = await gameRepo.searchCountrymenGames(
        countryCode: fideCode,
        query: query,
        minElo: _minElo,
        limit: _pageSize,
        offset: offset,
      );

      debugPrint('[CountrymenSearch] Supabase results: ${games.length}');

      return games.map((g) => GamesTourModel.fromGame(g)).toList();
    } catch (e) {
      debugPrint('[CountrymenSearch] Supabase error: $e');
      return [];
    }
  }

  /// Search Gamebase for countrymen games matching the query
  Future<List<GamesTourModel>> _searchGamebase(
    String countryName,
    String query,
    int page,
  ) async {
    try {
      final gamebaseRepo = _ref.read(gamebaseRepositoryProvider);

      // If we already have a working variation cached, use it directly
      if (_workingGamebaseVariation != null) {
        return _searchGamebaseWithVariation(
          gamebaseRepo,
          _workingGamebaseVariation!,
          query,
          page,
        );
      }

      // Otherwise, try all variations until one works (like _fetchFromGamebase does)
      final variations = CountryUtils.getGamebaseCountryVariations(countryName);
      debugPrint('[CountrymenSearch] Trying ${variations.length} country variations: $variations');

      for (final variation in variations) {
        final games = await _searchGamebaseWithVariation(
          gamebaseRepo,
          variation,
          query,
          page,
        );

        if (games.isNotEmpty) {
          // Cache the working variation for future searches
          _workingGamebaseVariation = variation;
          return games;
        }
      }

      return [];
    } catch (e) {
      debugPrint('[CountrymenSearch] Gamebase error: $e');
      return [];
    }
  }

  /// Helper to search Gamebase with a specific country variation
  Future<List<GamesTourModel>> _searchGamebaseWithVariation(
    GamebaseRepository gamebaseRepo,
    String countryVariation,
    String query,
    int page,
  ) async {
    final games = <GamesTourModel>[];

    final countryToken = countryVariation.contains(' ')
        ? 'country:"$countryVariation"'
        : 'country:$countryVariation';

    // Combine user query with country filter
    final fullQuery = '$query $countryToken';

    debugPrint('[CountrymenSearch] Gamebase query: $fullQuery, page=$page');

    final response = await gamebaseRepo.globalSearch(
      query: fullQuery,
      resources: ['game'],
      pageNumber: page,
      pageSize: _pageSize,
      ratingFrom: _minElo,
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

    return games;
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
      final countryCode = state.countryCode;
      final countryName = state.countryName;

      if (countryCode == null || countryCode.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          hasMore: false,
          error: 'No country selected',
        );
        return;
      }

      final newGames = <GamesTourModel>[];
      final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);

      // Reset offsets on initial load
      if (isInitial) {
        _supabaseRawOffset = 0;
        _workingGamebaseVariation = null;
      }

      int gamebasePageNumber = isInitial ? 1 : state.gamebasePageNumber;

      // Fetch from both sources in PARALLEL for faster loading
      Future<({List<GamesTourModel> games, int rawFetched})>? supabaseFuture;
      Future<List<GamesTourModel>>? gamebaseFuture;

      if (_supabaseHasMore) {
        supabaseFuture = _fetchFromSupabase(countryCode, _supabaseRawOffset);
      }
      if (_gamebaseHasMore && countryName != null) {
        gamebaseFuture = _fetchFromGamebase(countryName, gamebasePageNumber);
      }

      // Await both in parallel
      final supabaseResult = supabaseFuture != null ? await supabaseFuture : null;
      final gamebaseGames = gamebaseFuture != null ? await gamebaseFuture : null;

      // Process Supabase results
      if (supabaseResult != null) {
        final supabaseGames = supabaseResult.games;
        final rawFetched = supabaseResult.rawFetched;

        debugPrint('[CountrymenGames] Supabase: fetched ${supabaseGames.length} filtered games from $rawFetched raw (rawOffset: $_supabaseRawOffset)');

        // If raw fetch returned fewer than expected, Supabase is exhausted
        // (We fetch limit * 10 raw games, so if we get less than that, no more data)
        if (rawFetched < _pageSize * 10) {
          _supabaseHasMore = false;
          debugPrint('[CountrymenGames] Supabase exhausted: rawFetched=$rawFetched < ${_pageSize * 10}');
        }

        for (final game in supabaseGames) {
          final key = _generateDedupeKey(game);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            newGames.add(game);
          }
        }

        // Advance raw offset by how many raw games were actually fetched from DB
        _supabaseRawOffset += rawFetched;
      }

      // Process Gamebase results
      if (gamebaseGames != null) {
        debugPrint('[CountrymenGames] Gamebase returned ${gamebaseGames.length} games (page: $gamebasePageNumber)');

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

      debugPrint('[CountrymenGames] Total games now: ${allGames.length}, hasMore: $hasMore');

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: hasMore,
        gamebasePageNumber: gamebasePageNumber,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[CountrymenGames] Fetch error: $e');
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

  /// Fetch games from Supabase with proper pagination.
  /// Returns both filtered games and raw count for proper offset tracking.
  Future<({List<GamesTourModel> games, int rawFetched})> _fetchFromSupabase(
    String countryCode,
    int rawOffset,
  ) async {
    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      debugPrint('[CountrymenGames] Supabase query: fideCode=$fideCode, rawOffset=$rawOffset, limit=$_pageSize');

      // Fetch games with ELO filter applied - returns both filtered games AND raw count
      final result = await gameRepo.getCountrymanGamesWithMinEloAndRawCount(
        countryCode: fideCode,
        minElo: _minElo,
        limit: _pageSize,
        rawOffset: rawOffset,
      );

      debugPrint('[CountrymenGames] Supabase returned ${result.games.length} filtered games from ${result.rawFetched} raw');

      final games = result.games.map((game) => GamesTourModel.fromGame(game)).toList();
      return (games: games, rawFetched: result.rawFetched);
    } catch (e, st) {
      debugPrint('[CountrymenGames] Supabase error: $e\n$st');
      return (games: <GamesTourModel>[], rawFetched: 0);
    }
  }

  Future<List<GamesTourModel>> _fetchFromGamebase(
    String countryName,
    int page,
  ) async {
    try {
      final gamebaseRepo = _ref.read(gamebaseRepositoryProvider);
      final games = <GamesTourModel>[];

      // If we already found a working variation, use it directly
      List<String> variationsToTry;
      if (_workingGamebaseVariation != null) {
        variationsToTry = [_workingGamebaseVariation!];
      } else {
        // Get all country name variations (e.g., ['Türkiye', 'Turkey', 'Turkiye'])
        variationsToTry = CountryUtils.getGamebaseCountryVariations(countryName);
        debugPrint('[CountrymenGames] Gamebase: trying ${variationsToTry.length} country variations: $variationsToTry');
      }

      // Try each variation until we get results
      for (final variation in variationsToTry) {
        final query = variation.contains(' ')
            ? 'country:"$variation"'
            : 'country:$variation';

        debugPrint('[CountrymenGames] Gamebase query: $query, page=$page');

        final response = await gamebaseRepo.globalSearch(
          query: query,
          resources: ['game'], // Only fetch games, not players
          pageNumber: page,
          pageSize: _pageSize,
          ratingFrom: _minElo,
        );

        final gameResults = response.results.where((r) => r.resource == 'game');

        for (final result in gameResults) {
          final preview = result.preview ?? const <String, dynamic>{};
          final gameUuid = preview['id']?.toString() ?? result.id;

          final whiteElo = int.tryParse(preview['whiteElo']?.toString() ?? '') ?? 0;
          final blackElo = int.tryParse(preview['blackElo']?.toString() ?? '') ?? 0;

          if (whiteElo >= _minElo || blackElo >= _minElo) {
            final game = _convertGamebaseResultToModel(gameUuid, preview);
            if (game != null) {
              games.add(game);
            }
          }
        }

        debugPrint('[CountrymenGames] Query "$query" returned ${games.length} games');

        // If we got results, cache this variation for future pages
        if (games.isNotEmpty) {
          _workingGamebaseVariation = variation;
          break;
        }
      }

      return games;
    } catch (e) {
      debugPrint('[CountrymenGames] Gamebase error: $e');
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

      // Get federation info from the new whiteFed/blackFed fields
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
        roundId: 'countrymen_combined',
        roundSlug: eco ?? timeControl,
        tourId: event,
        pgn: pgn,
        lastMoveTime: date,
      );
    } catch (e) {
      debugPrint('[CountrymenGames] Convert error: $e');
      return null;
    }
  }
}
