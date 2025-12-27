import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
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

  const CountrymenCombinedGamesState({
    this.games = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.seenGameIds = const {},
    this.countryCode,
    this.countryName,
    this.searchQuery = '',
    this.filter = const GameFilter(),
  });

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

  // Track if Supabase has more data
  bool _supabaseHasMore = true;
  final List<GamesTourModel> _pendingGames = [];

  // Track RAW offset for Supabase (how many raw games we've fetched from DB)
  // This is different from filtered games count - we need to track raw to avoid skipping games
  int _supabaseRawOffset = 0;

  CountrymenCombinedGamesNotifier(this._ref)
      : super(const CountrymenCombinedGamesState(isLoading: true)) {
    _loadInitialGames();

    // Listen for country changes (temporary or persisted)
    _ref.listen<AsyncValue<Country>>(effectiveCountryProvider, (previous, next) {
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
      _supabaseHasMore = true;
      _supabaseRawOffset = 0;
      _pendingGames.clear();

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
    _supabaseRawOffset = 0;
    _pendingGames.clear();
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
    _supabaseRawOffset = 0;
    _pendingGames.clear();

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
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
    _supabaseRawOffset = 0;
    _pendingGames.clear();

    state = state.copyWith(
      isLoading: true,
      games: [],
      seenGameIds: {},
      hasMore: true,
      searchQuery: '',
      error: null,
    );

    await _fetchNextBatch(isInitial: true);
  }

  /// Fetch search results from Supabase
  Future<void> _fetchSearchResults({required bool isInitial}) async {
    if (!mounted) return;

    final countryCode = state.countryCode;
    final query = _currentSearchQuery;

    if (countryCode == null || countryCode.isEmpty || query.isEmpty) {
      state = state.copyWith(isLoading: false, hasMore: false);
      return;
    }

    try {
      final newGames = <GamesTourModel>[];
      final seenKeys = Set<String>.from(isInitial ? {} : state.seenGameIds);

      if (_supabaseHasMore) {
        final supabaseGames = await _searchSupabase(countryCode, query, _supabaseRawOffset);

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

      newGames.sort(_compareByDateDesc);

      final allGames = isInitial ? newGames : [...state.games, ...newGames];

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: _supabaseHasMore,
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

      if (isInitial) {
        _supabaseRawOffset = 0;
        _pendingGames.clear();
      }

      while (newGames.isEmpty && (_pendingGames.isNotEmpty || _supabaseHasMore)) {
        var rawDayGames = _takePendingDayRaw();
        if (rawDayGames.isEmpty) {
          rawDayGames = await _fetchNextDayFromSupabase(countryCode);
        }

        if (rawDayGames.isEmpty) {
          break;
        }

        for (final game in rawDayGames) {
          final key = _generateDedupeKey(game);
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            newGames.add(game);
          }
        }
      }

      newGames.sort(_compareByDateDesc);

      // Combine with existing games
      final allGames = isInitial ? newGames : [...state.games, ...newGames];

      debugPrint('[CountrymenGames] Total games now: ${allGames.length}, hasMore: $_supabaseHasMore');

      if (!mounted) return;

      state = state.copyWith(
        games: allGames,
        isLoading: false,
        hasMore: _supabaseHasMore || _pendingGames.isNotEmpty,
        seenGameIds: seenKeys,
      );
    } catch (e) {
      debugPrint('[CountrymenGames] Fetch error: $e');
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

  List<GamesTourModel> _takePendingDayRaw() {
    if (_pendingGames.isEmpty) return [];

    final targetDayKey = _dayKeyForGame(_pendingGames.first);
    final remaining = <GamesTourModel>[];
    final dayGames = <GamesTourModel>[];

    for (final game in _pendingGames) {
      final dayKey = _dayKeyForGame(game);
      if (dayKey == targetDayKey) {
        dayGames.add(game);
      } else {
        remaining.add(game);
      }
    }

    _pendingGames
      ..clear()
      ..addAll(remaining);

    return dayGames;
  }

  Future<List<GamesTourModel>> _fetchNextDayFromSupabase(
    String countryCode,
  ) async {
    String? targetDayKey;
    final dayGames = <GamesTourModel>[];
    var reachedNextDay = false;

    while (_supabaseHasMore && !reachedNextDay) {
      final result = await _fetchRawFromSupabase(countryCode, _supabaseRawOffset);
      final supabaseGames = result.games;
      final rawFetched = result.rawFetched;

      debugPrint('[CountrymenGames] Supabase returned ${supabaseGames.length} raw games (rawOffset: $_supabaseRawOffset)');

      if (supabaseGames.isEmpty) {
        _supabaseHasMore = false;
        break;
      }

      _supabaseRawOffset += rawFetched;
      if (rawFetched < _pageSize) {
        _supabaseHasMore = false;
      }

      supabaseGames.sort(_compareByDateDesc);

      for (var i = 0; i < supabaseGames.length; i++) {
        final game = supabaseGames[i];
        final dayKey = _dayKeyForGame(game);
        targetDayKey ??= dayKey;

        if (dayKey == targetDayKey) {
          dayGames.add(game);
        } else {
          _pendingGames.addAll(supabaseGames.sublist(i));
          reachedNextDay = true;
          break;
        }
      }
    }

    return dayGames;
  }

  Future<({List<GamesTourModel> games, int rawFetched})> _fetchRawFromSupabase(
    String countryCode,
    int rawOffset,
  ) async {
    try {
      final gameRepo = _ref.read(gameRepositoryProvider);
      final fideCode = CountryUtils.toFideCode(countryCode);

      debugPrint('[CountrymenGames] Supabase query: fideCode=$fideCode, rawOffset=$rawOffset, limit=$_pageSize');

      final supabaseGames = await gameRepo.getGamesByCountryCodePaginated(
        countryCode: fideCode,
        limit: _pageSize,
        offset: rawOffset,
      );

      final games = supabaseGames.map((game) => GamesTourModel.fromGame(game)).toList();
      return (games: games, rawFetched: supabaseGames.length);
    } catch (e, st) {
      debugPrint('[CountrymenGames] Supabase error: $e\n$st');
      return (games: <GamesTourModel>[], rawFetched: 0);
    }
  }

  int _compareByDateDesc(GamesTourModel a, GamesTourModel b) {
    final aDayKey = _dayKeyForGame(a);
    final bDayKey = _dayKeyForGame(b);
    final dayCompare = bDayKey.compareTo(aDayKey);
    if (dayCompare != 0) {
      return dayCompare;
    }

    final eloCompare = b.cardElo.compareTo(a.cardElo);
    if (eloCompare != 0) {
      return eloCompare;
    }

    final aTime = a.lastMoveTime ?? DateTime(1900);
    final bTime = b.lastMoveTime ?? DateTime(1900);
    return bTime.compareTo(aTime);
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
    debugPrint('[CountrymenGames] Applying filter: result=${filter.result}, color=${filter.color}, timeControl=${filter.timeControl}');
    state = state.copyWith(filter: filter);
  }

  /// Clear all filters
  void clearFilter() {
    debugPrint('[CountrymenGames] Clearing filter');
    state = state.copyWith(filter: GameFilter.defaultFilter());
  }
}
