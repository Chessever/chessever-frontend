import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============================================================================
// PROVIDER DEFINITIONS
// ============================================================================

/// Provider for the current search query used in search tab
final searchTabQueryProvider = StateProvider<String>((ref) => '');

/// Main provider for Search tab games - fetches games for top players matching search
final searchGamesProvider = StateNotifierProvider.autoDispose<
    SearchGamesNotifier, AsyncValue<List<Games>>>((ref) {
  return SearchGamesNotifier(ref);
});

/// Provider for grouped games (by tournament) for UI display
final groupedSearchGamesProvider =
    Provider.autoDispose<List<GroupedSearchGames>>((ref) {
  final games = ref.watch(searchGamesProvider).valueOrNull ?? [];

  // Group games by tournament
  final grouped = <String, GroupedSearchGames>{};
  final groupOrder = <String>[];

  for (final game in games) {
    final tourId = game.tourId;
    final tourName = game.tourSlug;

    if (!grouped.containsKey(tourId)) {
      grouped[tourId] = GroupedSearchGames(
        tourId: tourId,
        tourName: tourName,
        games: [],
        hasLiveGames: false,
      );
      groupOrder.add(tourId);
    }

    if (grouped[tourId]!.tourName.isEmpty) {
      grouped[tourId] = GroupedSearchGames(
        tourId: tourId,
        tourName: tourName,
        games: grouped[tourId]!.games,
        hasLiveGames: grouped[tourId]!.hasLiveGames,
      );
    }

    grouped[tourId]!.games.add(game);
    if (game.status == '*') {
      grouped[tourId]!.hasLiveGames = true;
    }
  }

  return groupOrder
      .where((id) => grouped[id]!.games.isNotEmpty)
      .map((tourId) => grouped[tourId]!)
      .toList();
});

/// Provider for converted games (Games to GamesTourModel)
final convertedSearchGamesProvider =
    Provider.autoDispose<List<GamesTourModel>>((ref) {
  final games = ref.watch(searchGamesProvider).valueOrNull ?? [];
  return games.map((game) => GamesTourModel.fromGame(game)).toList();
});

/// Global set to track which game IDs have been animated in search tab
final searchAnimatedGameIds = <String>{};

// ============================================================================
// STATE NOTIFIER
// ============================================================================

/// Notifier for managing Search tab games state
class SearchGamesNotifier extends StateNotifier<AsyncValue<List<Games>>> {
  SearchGamesNotifier(this._ref) : super(const AsyncValue.data([]));

  final Ref _ref;
  final List<Games> _allGames = [];
  String _currentQuery = '';
  bool _isFetching = false;
  Timer? _debounceTimer;

  /// Maximum number of top players to fetch games for
  static const int _maxPlayers = 4;

  /// Load games for top players matching search query
  Future<void> loadGamesForSearch(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      _currentQuery = '';
      _allGames.clear();
      searchAnimatedGameIds.clear();
      state = const AsyncValue.data([]);
      return;
    }

    // Debounce rapid typing
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      await _performSearch(trimmedQuery);
    });
  }

  Future<void> _performSearch(String query) async {
    if (_isFetching && query == _currentQuery) return;

    _isFetching = true;
    _currentQuery = query;

    try {
      state = const AsyncValue.loading();
      _allGames.clear();
      searchAnimatedGameIds.clear();

      final gameRepository = _ref.read(gameRepositoryProvider);

      // Get search results from combined search provider
      // This already sorts by relevancy then ELO
      final searchResults = await _ref.read(
        supabaseCombinedSearchProvider(query).future,
      );

      // Get player results (already sorted by relevancy then ELO) and take top 4
      final playerResults = searchResults.playerResults
          .where((r) => r.player != null)
          .take(_maxPlayers)
          .toList();

      debugPrint('[SearchGames] Found ${playerResults.length} top players for "$query"');

      if (playerResults.isEmpty) {
        state = const AsyncValue.data([]);
        _isFetching = false;
        return;
      }

      // Fetch games for each player
      final allGames = <Games>[];

      for (final result in playerResults) {
        final playerName = result.player!.name;
        try {
          final games = await gameRepository.getGamesByPlayerName(
            playerName,
            limit: 10,
          );
          allGames.addAll(games);
          debugPrint('[SearchGames] Fetched ${games.length} games for $playerName');
        } catch (e) {
          debugPrint('[SearchGames] Error fetching games for $playerName: $e');
        }
      }

      // Sort all games by datetime ascending (earliest first)
      allGames.sort((a, b) {
        final aTime = a.lastMoveTime;
        final bTime = b.lastMoveTime;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });

      // Remove duplicates (same game might appear for multiple players)
      final uniqueGames = <String, Games>{};
      for (final game in allGames) {
        uniqueGames[game.id] = game;
      }

      _allGames.addAll(uniqueGames.values);
      state = AsyncValue.data(List<Games>.from(_allGames));
    } catch (e, stack) {
      debugPrint('[SearchGames] Error loading search games: $e');
      state = AsyncValue.error(e, stack);
    } finally {
      _isFetching = false;
    }
  }

  /// Clear search results
  void clearSearch() {
    _debounceTimer?.cancel();
    _currentQuery = '';
    _allGames.clear();
    searchAnimatedGameIds.clear();
    state = const AsyncValue.data([]);
  }

  /// Refresh search results
  Future<void> refresh() async {
    if (_currentQuery.isNotEmpty) {
      _isFetching = false;
      await _performSearch(_currentQuery);
    }
  }

  bool get isFetching => _isFetching;
  String get currentQuery => _currentQuery;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// MODELS
// ============================================================================

/// Represents games grouped by tournament for search UI display
class GroupedSearchGames {
  GroupedSearchGames({
    required this.tourId,
    required this.tourName,
    required this.games,
    required this.hasLiveGames,
  });

  final String tourId;
  String tourName;
  final List<Games> games;
  bool hasLiveGames;
}
