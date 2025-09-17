import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:chessever2/widgets/search/gameSearch/model/game_search_state.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'dart:async';

final gameSearchStateProvider = StateNotifierProvider.family
    .autoDispose<_GameSearchController, GameSearchState, String>(
      (ref, query) => _GameSearchController(ref, query),
    );

class _GameSearchController extends StateNotifier<GameSearchState> {
  _GameSearchController(this.ref, this.query) : super(const GameSearchState()) {
    _initialize();
  }

  final Ref ref;
  final String query;

  Timer? _searchDebouncer;
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  // Caching
  Map<String, List<GameSearchResult>> _searchCache = {};
  static const int _maxCacheSize = 30;
  static const Duration _cacheExpiry = Duration(minutes: 5);
  Map<String, DateTime> _cacheTimestamps = {};

  // Round ordering
  Map<String, int>? _roundOrderMap;
  List<GamesAppBarModel>? _cachedRounds;

  // Tournament tracking
  String? _currentTourId;

  void _initialize() {
    _loadRoundOrder();
    search();
  }

  /// Load round order from provider
  void _loadRoundOrder() {
    try {
      final gamesAppBarAsync = ref.read(gamesAppBarProvider);
      if (gamesAppBarAsync.hasValue) {
        final rounds = gamesAppBarAsync.value?.gamesAppBarModels ?? [];
        if (rounds.isNotEmpty) {
          _cacheRoundOrder(rounds);
          state = state.copyWith(isInitialized: true);
        }
      }
    } catch (e) {
      debugPrint('Error loading round order: $e');
    }
  }

  void _cacheRoundOrder(List<GamesAppBarModel> rounds) {
    _cachedRounds = List.unmodifiable(rounds);
    _roundOrderMap = {};

    final reversedRounds = rounds.reversed.toList();
    for (int i = 0; i < reversedRounds.length; i++) {
      final roundId = reversedRounds[i].id;
      if (roundId.isNotEmpty) {
        _roundOrderMap![roundId] = i;
      }
    }

    debugPrint('Cached ${rounds.length} rounds for sorting');
  }

  String? get _tourId {
    try {
      return ref.read(tourDetailScreenProvider).value?.aboutTourModel.id;
    } catch (e) {
      return null;
    }
  }

  void search() {
    // Cancel any pending search
    _searchDebouncer?.cancel();

    final trimmedQuery = query.trim();

    // Handle empty query - clear everything
    if (trimmedQuery.isEmpty) {
      state = state.copyWith(
        currentQuery: '',
        results: [],
        isSearching: false,
        clearError: true,
      );
      return;
    }

    final shouldShowSearching =
        state.results.isEmpty || state.currentQuery.isEmpty;

    state = state.copyWith(
      currentQuery: query,
      clearError: true,
      // Keep existing results while searching for new query
      // Only show searching indicator if we don't have any results yet
      isSearching: shouldShowSearching,
    );

    // Debounce the actual search
    _searchDebouncer = Timer(_debounceDelay, () {
      _executeSearch(query);
    });
  }

  /// Execute the actual search
  Future<void> _executeSearch(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    // Check tournament
    final tourId = _tourId;
    if (tourId == null) {
      state = state.copyWith(
        errorMessage: 'No tournament selected',
        isSearching: false,
      );
      return;
    }

    // Check if tournament changed
    if (_currentTourId != tourId) {
      _clearCache();
      _currentTourId = tourId;
      debugPrint('Tournament changed, cleared cache');
    }

    // Check cache
    final cacheKey = '${tourId}_${trimmedQuery.toLowerCase()}';
    final cachedResults = _getCachedResults(cacheKey);

    if (cachedResults != null) {
      debugPrint('Using cached results for: $query');
      state = state.copyWith(
        results: _sortResults(cachedResults),
        isSearching: false,
        lastSearchTimestamp: DateTime.now(),
      );
      return;
    }

    // Update to show searching if we're actually fetching new data
    state = state.copyWith(isSearching: true);

    try {
      // Perform the actual search
      final searchResult = await ref
          .read(gamesLocalStorage)
          .searchGamesWithScoring(tourId: tourId, query: trimmedQuery);

      final results = searchResult.results;

      // Cache the results
      _cacheResults(cacheKey, results);

      // Only update results if this search is still relevant
      // (user hasn't changed query in the meantime)
      if (state.currentQuery == query) {
        state = state.copyWith(
          results: _sortResults(results),
          isSearching: false,
          lastSearchTimestamp: DateTime.now(),
        );

        debugPrint('Search completed: ${results.length} results for "$query"');
      } else {
        debugPrint(
          'Search results ignored - query changed from "$query" to "${state.currentQuery}"',
        );
      }
    } catch (e) {
      debugPrint('Search error: $e');
      // Only show error if this search is still relevant
      if (state.currentQuery == query) {
        state = state.copyWith(
          errorMessage: 'Search failed. Please try again.',
          isSearching: false,
        );
      }
    }
  }

  /// Get cached results if still valid
  List<GameSearchResult>? _getCachedResults(String key) {
    final results = _searchCache[key];
    final timestamp = _cacheTimestamps[key];

    if (results != null && timestamp != null) {
      final age = DateTime.now().difference(timestamp);
      if (age < _cacheExpiry) {
        return results;
      } else {
        // Remove expired cache
        _searchCache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }

    return null;
  }

  /// Cache search results
  void _cacheResults(String key, List<GameSearchResult> results) {
    _searchCache[key] = results;
    _cacheTimestamps[key] = DateTime.now();

    // Limit cache size
    if (_searchCache.length > _maxCacheSize) {
      _cleanupCache();
    }
  }

  /// Clean up old cache entries
  void _cleanupCache() {
    // Sort entries by timestamp
    final entries =
        _cacheTimestamps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    // Remove oldest entries
    final toRemove = entries.take(entries.length - _maxCacheSize ~/ 2);
    for (final entry in toRemove) {
      _searchCache.remove(entry.key);
      _cacheTimestamps.remove(entry.key);
    }
  }

  /// Sort results by round order
  List<GameSearchResult> _sortResults(List<GameSearchResult> results) {
    if (results.isEmpty || _roundOrderMap == null) {
      return results;
    }

    final sorted = List<GameSearchResult>.from(results);

    sorted.sort((a, b) {
      // Primary: Round order
      final roundAOrder = _roundOrderMap![a.game.roundId] ?? 999;
      final roundBOrder = _roundOrderMap![b.game.roundId] ?? 999;

      final roundComparison = roundAOrder.compareTo(roundBOrder);
      if (roundComparison != 0) return roundComparison;

      // Secondary: Board number
      final aBoardNr = a.game.boardNr;
      final bBoardNr = b.game.boardNr;

      if (aBoardNr != null && bBoardNr != null) {
        final boardComparison = aBoardNr.compareTo(bBoardNr);
        if (boardComparison != 0) return boardComparison;
      }

      if (aBoardNr != null && bBoardNr == null) return -1;
      if (aBoardNr == null && bBoardNr != null) return 1;

      // Tertiary: Player names
      final aPlayers = a.game.players?.map((p) => p.name).join('') ?? '';
      final bPlayers = b.game.players?.map((p) => p.name).join('') ?? '';

      return aPlayers.compareTo(bPlayers);
    });

    return sorted;
  }

  /// Clear all caches
  void _clearCache() {
    _searchCache.clear();
    _cacheTimestamps.clear();
  }

  /// Force refresh round order
  Future<void> refreshRoundOrder() async {
    _roundOrderMap = null;
    _cachedRounds = null;

    ref.invalidate(gamesAppBarProvider);
    await Future.delayed(const Duration(milliseconds: 100));

    _loadRoundOrder();
  }

  /// Clear search results
  void clearSearch() {
    _searchDebouncer?.cancel();
    state = const GameSearchState();
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _clearCache();
    super.dispose();
  }
}
