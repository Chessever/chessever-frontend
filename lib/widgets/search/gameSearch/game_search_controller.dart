import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import '../../../screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import '../../../screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'dart:async';

final gameSearchProvider = AutoDisposeProvider(
  (ref) => _EnhancedGamesSearchController(ref),
);

class _EnhancedGamesSearchController {
  _EnhancedGamesSearchController(this.ref) {
    _initializeController();
  }

  final Ref ref;

  // Cached data
  List<GamesAppBarModel>? _cachedRounds;
  Map<String, int>? _cachedRoundOrder;
  Map<String, EnhancedGameSearchResult> _searchCache = {};

  // State management
  bool _isInitialized = false;
  String? _lastTourId;
  Timer? _cacheCleanupTimer;

  // Constants
  static const int _maxCacheSize = 50;
  static const Duration _cacheCleanupInterval = Duration(minutes: 5);
  static const Duration _cacheExpiry = Duration(minutes: 10);

  void _initializeController() {
    _startCacheCleanupTimer();
  }

  void _startCacheCleanupTimer() {
    _cacheCleanupTimer = Timer.periodic(_cacheCleanupInterval, (_) {
      _cleanupExpiredCache();
    });
  }

  void _cleanupExpiredCache() {
    if (_searchCache.length > _maxCacheSize) {
      // Keep only the most recent searches
      final entries = _searchCache.entries.toList();
      entries.sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));

      _searchCache.clear();
      _searchCache.addEntries(entries.take(_maxCacheSize ~/ 2));
    }
  }

  /// Initialize round order from the provider
  void initializeRoundOrder() {
    try {
      final gamesAppBarAsync = ref.read(gamesAppBarProvider);
      if (gamesAppBarAsync.hasValue) {
        final rounds = gamesAppBarAsync.value?.gamesAppBarModels ?? [];
        _cacheRoundOrder(rounds);
        _isInitialized = true;
      }
    } catch (e) {
      debugPrint('Error initializing round order: $e');
    }
  }

  /// Cache the round order for efficient sorting
  void _cacheRoundOrder(List<GamesAppBarModel> rounds) {
    if (rounds.isEmpty) return;

    _cachedRounds = List.unmodifiable(rounds);
    _cachedRoundOrder = _buildRoundOrderMap(rounds);

    debugPrint('Cached ${rounds.length} rounds for sorting');
  }

  /// Build an efficient lookup map for round ordering
  Map<String, int> _buildRoundOrderMap(List<GamesAppBarModel> rounds) {
    final roundOrder = <String, int>{};
    final reversedRounds = rounds.reversed.toList();

    for (int i = 0; i < reversedRounds.length; i++) {
      final roundId = reversedRounds[i].id;
      if (roundId.isNotEmpty) {
        roundOrder[roundId] = i;
      }
    }

    return Map.unmodifiable(roundOrder);
  }

  /// Get the currently selected tournament ID
  String? get selectedTourId {
    try {
      return ref.watch(tourDetailScreenProvider).value?.aboutTourModel.id;
    } catch (e) {
      debugPrint('Error getting selected tour ID: $e');
      return null;
    }
  }

  /// Check if round order has been cached
  bool get hasRoundOrderCached =>
      _cachedRoundOrder != null && _cachedRoundOrder!.isNotEmpty;

  /// Get cached rounds (read-only)
  List<GamesAppBarModel>? get cachedRounds => _cachedRounds;

  /// Get initialization status
  bool get isInitialized => _isInitialized;

  /// Search games with caching and error handling
  Future<EnhancedGameSearchResult> searchGames(String query) async {
    if (query.trim().isEmpty) {
      return EnhancedGameSearchResult(results: [], timestamp: DateTime.now());
    }

    final tourId = selectedTourId;
    if (tourId == null) {
      throw StateError('No tournament selected');
    }

    // Check if tournament changed and clear cache if needed
    if (_lastTourId != null && _lastTourId != tourId) {
      _searchCache.clear();
      debugPrint('Tournament changed, cleared search cache');
    }
    _lastTourId = tourId;

    // Check cache first
    final cacheKey = '${tourId}_${query.toLowerCase().trim()}';
    final cachedResult = _searchCache[cacheKey];

    if (cachedResult != null &&
        DateTime.now().difference(cachedResult.timestamp) < _cacheExpiry) {
      debugPrint('Using cached search result for: $query');
      return cachedResult;
    }

    // Perform search
    try {
      final result = await ref
          .read(gamesLocalStorage)
          .searchGamesWithScoring(tourId: tourId, query: query.trim());

      // Update cache
      final timestampedResult = EnhancedGameSearchResult(
        results: result.results,
        timestamp: DateTime.now(),
      );

      _searchCache[cacheKey] = timestampedResult;

      debugPrint(
        'Search completed: ${result.results.length} results for "$query"',
      );
      return timestampedResult;
    } catch (e) {
      debugPrint('Search failed for "$query": $e');
      rethrow;
    }
  }

  /// Sort search results by round order with enhanced logic
  List<GameSearchResult> sortSearchResultsByRoundOrder(
    List<GameSearchResult> results,
  ) {
    if (results.isEmpty || _cachedRoundOrder == null) {
      return results;
    }

    final sortedResults = List<GameSearchResult>.from(results);

    try {
      sortedResults.sort((a, b) {
        // Primary sort: Round order
        final roundAOrder = _cachedRoundOrder![a.game.roundId] ?? 999;
        final roundBOrder = _cachedRoundOrder![b.game.roundId] ?? 999;

        final roundComparison = roundAOrder.compareTo(roundBOrder);
        if (roundComparison != 0) return roundComparison;

        // Secondary sort: Board number
        final aBoardNr = a.game.boardNr;
        final bBoardNr = b.game.boardNr;

        if (aBoardNr != null && bBoardNr != null) {
          final boardComparison = aBoardNr.compareTo(bBoardNr);
          if (boardComparison != 0) return boardComparison;
        }

        // Handle null board numbers
        if (aBoardNr != null && bBoardNr == null) return -1;
        if (aBoardNr == null && bBoardNr != null) return 1;

        // Tertiary sort: Player names for consistency
        final aPlayerNames = a.game.players?.map((p) => p.name).join('') ?? '';
        final bPlayerNames = b.game.players?.map((p) => p.name).join('') ?? '';

        return aPlayerNames.compareTo(bPlayerNames);
      });

      debugPrint('Sorted ${results.length} search results by round order');
      return sortedResults;
    } catch (e) {
      debugPrint('Error sorting search results: $e');
      return results; // Return original order on error
    }
  }

  /// Try to initialize from provider with better error handling
  void tryInitializeFromProvider() {
    if (_isInitialized) return;

    try {
      final gamesAppBarAsync = ref.watch(gamesAppBarProvider);

      if (gamesAppBarAsync.hasValue) {
        // Use post-frame callback to ensure UI is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isInitialized) {
            final rounds = gamesAppBarAsync.value?.gamesAppBarModels ?? [];
            if (rounds.isNotEmpty) {
              _cacheRoundOrder(rounds);
              _isInitialized = true;
            }
          }
        });
      } else if (gamesAppBarAsync.hasError) {
        debugPrint('Error in gamesAppBarProvider: ${gamesAppBarAsync.error}');
      }
    } catch (e) {
      debugPrint('Error trying to initialize from provider: $e');
    }
  }

  /// Force refresh the round order cache
  Future<void> refreshRoundOrder() async {
    try {
      _isInitialized = false;
      _cachedRounds = null;
      _cachedRoundOrder = null;

      // Invalidate the provider to force refresh
      ref.invalidate(gamesAppBarProvider);

      // Wait a bit for the provider to refresh
      await Future.delayed(const Duration(milliseconds: 100));

      tryInitializeFromProvider();
    } catch (e) {
      debugPrint('Error refreshing round order: $e');
    }
  }

  /// Clear all caches
  void clearCaches() {
    _searchCache.clear();
    _cachedRounds = null;
    _cachedRoundOrder = null;
    _isInitialized = false;
    _lastTourId = null;
    debugPrint('Cleared all search caches');
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'searchCacheSize': _searchCache.length,
      'isInitialized': _isInitialized,
      'hasRoundOrderCached': hasRoundOrderCached,
      'cachedRoundsCount': _cachedRounds?.length ?? 0,
      'lastTourId': _lastTourId,
    };
  }

  /// Dispose resources
  void dispose() {
    _cacheCleanupTimer?.cancel();
    _searchCache.clear();
    debugPrint('Games search controller disposed');
  }
}

// Extension to add timestamp to search results for caching
extension EnhancedGameSearchResultTimestamp on EnhancedGameSearchResult {
  EnhancedGameSearchResult copyWith({
    List<GameSearchResult>? results,
    DateTime? timestamp,
  }) {
    return EnhancedGameSearchResult(
      results: results ?? this.results,
      timestamp: timestamp ?? DateTime.now(),
    );
  }
}
