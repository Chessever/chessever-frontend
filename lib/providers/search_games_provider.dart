import 'dart:async';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
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

/// Provider for grouped games (by event/group_broadcast) for UI display
/// Uses tour_id to group_broadcast_id mapping to properly group multiple rounds of same event
final groupedSearchGamesProvider =
    FutureProvider.autoDispose<List<GroupedSearchGames>>((ref) async {
  final games = ref.watch(searchGamesProvider).valueOrNull ?? [];

  if (games.isEmpty) return [];

  // Get unique tour IDs from games
  final uniqueTourIds = games.map((g) => g.tourId).toSet().toList();

  // Fetch tour data to get group_broadcast_id mapping
  final tourRepository = ref.read(tourRepositoryProvider);
  final groupBroadcastRepository = ref.read(groupBroadcastRepositoryProvider);
  final tours = await tourRepository.getToursByIds(uniqueTourIds);

  // Create a mapping from tour_id to group_broadcast_id
  final tourToGroupBroadcast = <String, String>{};
  final uniqueGroupBroadcastIds = <String>{};

  for (final tour in tours) {
    // Use group_broadcast_id if available, otherwise fall back to tour.id
    final groupId = tour.groupBroadcastId ?? tour.id;
    tourToGroupBroadcast[tour.id] = groupId;
    uniqueGroupBroadcastIds.add(groupId);
  }

  // Fetch actual group_broadcast names from the group_broadcasts table
  // This ensures we get the parent event name, not individual tour/qualifier names
  final groupBroadcastNames = <String, String>{};
  for (final groupId in uniqueGroupBroadcastIds) {
    try {
      final groupBroadcast = await groupBroadcastRepository.getGroupBroadcastById(groupId);
      groupBroadcastNames[groupId] = groupBroadcast.name;
    } catch (e) {
      // Fallback: find the shortest tour name for this group (likely the parent name)
      final toursInGroup = tours.where((t) => (t.groupBroadcastId ?? t.id) == groupId);
      if (toursInGroup.isNotEmpty) {
        // Use shortest name as it's usually the base event name without qualifiers
        final shortestName = toursInGroup
            .map((t) => t.name)
            .reduce((a, b) => a.length <= b.length ? a : b);
        groupBroadcastNames[groupId] = shortestName;
      }
    }
  }

  // Group games by group_broadcast_id (event level, not round level)
  final grouped = <String, GroupedSearchGames>{};
  final groupOrder = <String>[];

  for (final game in games) {
    // Look up the group_broadcast_id for this tour, fallback to tour_id if not found
    final groupBroadcastId = tourToGroupBroadcast[game.tourId] ?? game.tourId;
    final groupName = groupBroadcastNames[groupBroadcastId] ?? game.tourSlug;

    if (!grouped.containsKey(groupBroadcastId)) {
      grouped[groupBroadcastId] = GroupedSearchGames(
        tourId: groupBroadcastId, // Using group_broadcast_id as the ID for navigation
        tourName: groupName,
        games: [],
        hasLiveGames: false,
      );
      groupOrder.add(groupBroadcastId);
    }

    grouped[groupBroadcastId]!.games.add(game);
    if (game.status == '*') {
      grouped[groupBroadcastId]!.hasLiveGames = true;
    }
  }

  return groupOrder
      .where((id) => grouped[id]!.games.isNotEmpty)
      .map((groupId) => grouped[groupId]!)
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

    // Immediately show loading state to avoid "No Games Found" flash
    // This prevents the empty state from showing during debounce
    if (!state.isLoading) {
      state = const AsyncValue.loading();
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

      // Deduplicate players by name and keep the one with highest rating
      // This ensures we don't fetch games for the same player multiple times
      final playersByName = <String, SearchResult>{};
      for (final result in searchResults.playerResults) {
        if (result.player == null) continue;
        final name = result.player!.name;
        final existingResult = playersByName[name];
        if (existingResult == null ||
            (result.player!.rating ?? 0) > (existingResult.player!.rating ?? 0)) {
          playersByName[name] = result;
        }
      }

      // Sort deduplicated players by rating (highest first) and take top players
      final uniquePlayerResults = playersByName.values.toList()
        ..sort((a, b) {
          final aRating = a.player?.rating ?? 0;
          final bRating = b.player?.rating ?? 0;
          return bRating.compareTo(aRating);
        });

      final topPlayers = uniquePlayerResults.take(_maxPlayers).toList();

      debugPrint('[SearchGames] Found ${topPlayers.length} unique top players for "$query"');
      for (final p in topPlayers) {
        debugPrint('[SearchGames] - ${p.player!.name} (ELO: ${p.player!.rating}, FIDE: ${p.player!.fideId})');
      }

      if (topPlayers.isEmpty) {
        state = const AsyncValue.data([]);
        _isFetching = false;
        return;
      }

      // Fetch ALL games for the highest ELO player (to show all their events)
      // No limit applied - ensures we get all tournaments where this player participated
      final allGames = <Games>[];
      final topPlayer = topPlayers.first.player!;

      try {
        List<Games> games;
        if (topPlayer.fideId != null) {
          // Use FIDE ID if available (more reliable)
          // No limit - fetch ALL games to ensure all events are captured
          games = await gameRepository.getGamesByFideId(
            topPlayer.fideId.toString(),
          );
          debugPrint('[SearchGames] Fetched ${games.length} games for ${topPlayer.name} by FIDE ID ${topPlayer.fideId}');
        } else {
          // Fallback to player name - no limit
          games = await gameRepository.getGamesByPlayerName(
            topPlayer.name,
          );
          debugPrint('[SearchGames] Fetched ${games.length} games for ${topPlayer.name} by name');
        }
        allGames.addAll(games);
      } catch (e) {
        debugPrint('[SearchGames] Error fetching games for ${topPlayer.name}: $e');
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
