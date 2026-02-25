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

/// Main provider for Search tab games - fetches games for top players matching search
///
/// NOTE: Using keepAlive to prevent data loss when scrolling/interacting.
/// This ensures consistent search results and scroll position preservation.
final searchGamesProvider = StateNotifierProvider.autoDispose<
  SearchGamesNotifier,
  AsyncValue<List<Games>>
>((ref) {
  // CRITICAL: Keep provider alive during search session to prevent:
  // 1. Data discrepancy when scrolling/interacting
  // 2. Re-fetching games unnecessarily
  // 3. Search results changing unexpectedly
  ref.keepAlive();

  return SearchGamesNotifier(ref);
});

/// Provider for grouped games (by event/group_broadcast) for UI display
/// Uses tour_id to group_broadcast_id mapping to properly group multiple rounds of same event
final groupedSearchGamesProvider = FutureProvider.autoDispose<
  List<GroupedSearchGames>
>((ref) async {
  ref.keepAlive(); // Keep alive to match main provider

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
      final groupBroadcast = await groupBroadcastRepository
          .getGroupBroadcastById(groupId);
      groupBroadcastNames[groupId] = groupBroadcast.name;
    } catch (e) {
      // Fallback: find the shortest tour name for this group (likely the parent name)
      final toursInGroup = tours.where(
        (t) => (t.groupBroadcastId ?? t.id) == groupId,
      );
      if (toursInGroup.isNotEmpty) {
        // Use shortest name as it's usually the base event name without qualifiers
        final shortestName = toursInGroup
            .map((t) => t.name)
            .reduce((a, b) => a.length <= b.length ? a : b);
        groupBroadcastNames[groupId] = shortestName;
      }
    }
  }

  // Create a mapping from tour_id to tour createdAt for date sorting
  final tourDates = <String, DateTime>{};
  for (final tour in tours) {
    tourDates[tour.id] = tour.createdAt;
  }

  // Group games by group_broadcast_id (event level, not round level)
  final grouped = <String, GroupedSearchGames>{};
  final groupOrder = <String>[];

  for (final game in games) {
    // Look up the group_broadcast_id for this tour, fallback to tour_id if not found
    final groupBroadcastId = tourToGroupBroadcast[game.tourId] ?? game.tourId;
    final groupName = groupBroadcastNames[groupBroadcastId] ?? game.tourSlug;

    if (!grouped.containsKey(groupBroadcastId)) {
      // Find the most recent tour date for this group
      DateTime? groupDate;
      for (final tour in tours) {
        if ((tour.groupBroadcastId ?? tour.id) == groupBroadcastId) {
          if (groupDate == null || tour.createdAt.isAfter(groupDate)) {
            groupDate = tour.createdAt;
          }
        }
      }

      grouped[groupBroadcastId] = GroupedSearchGames(
        tourId:
            groupBroadcastId, // Using group_broadcast_id as the ID for navigation
        tourName: groupName,
        games: [],
        hasLiveGames: false,
        tournamentDate: groupDate,
      );
      groupOrder.add(groupBroadcastId);
    }

    grouped[groupBroadcastId]!.games.add(game);
    if (game.status == '*') {
      grouped[groupBroadcastId]!.hasLiveGames = true;
    }
  }

  // Build the result list and sort groups by relevance
  final result =
      groupOrder
          .where((id) => grouped[id]!.games.isNotEmpty)
          .map((groupId) => grouped[groupId]!)
          .toList();

  // Sort groups: live events first, then by tournament date (most recent first)
  result.sort((a, b) {
    // 1. Live events first
    if (a.hasLiveGames != b.hasLiveGames) {
      return a.hasLiveGames ? -1 : 1;
    }

    // 2. Sort by tournament date (most recent first)
    final aDate = a.tournamentDate;
    final bDate = b.tournamentDate;

    if (aDate != null && bDate != null) {
      return bDate.compareTo(aDate); // Descending - most recent first
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }

    // 3. Fallback: sort by most recent game activity in the group
    DateTime? getMostRecentGameDate(GroupedSearchGames group) {
      DateTime? mostRecent;
      for (final game in group.games) {
        if (game.lastMoveTime != null) {
          if (mostRecent == null || game.lastMoveTime!.isAfter(mostRecent)) {
            mostRecent = game.lastMoveTime;
          }
        }
      }
      return mostRecent;
    }

    final aGameDate = getMostRecentGameDate(a);
    final bGameDate = getMostRecentGameDate(b);

    if (aGameDate != null && bGameDate != null) {
      return bGameDate.compareTo(aGameDate);
    } else if (aGameDate != null) {
      return -1;
    } else if (bGameDate != null) {
      return 1;
    }

    return 0;
  });

  return result;
});

/// Provider for converted games (Games to GamesTourModel)
final convertedSearchGamesProvider = Provider.autoDispose<List<GamesTourModel>>(
  (ref) {
    ref.keepAlive(); // Keep alive to match main provider

    final games = ref.watch(searchGamesProvider).valueOrNull ?? [];
    return games.map((game) => GamesTourModel.fromGame(game)).toList();
  },
);

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
  static const int _countryFallbackLimit = 40;

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

    // CRITICAL: Skip if we already have valid results for this exact query
    // This prevents unnecessary re-fetches when scrolling/interacting
    if (trimmedQuery == _currentQuery && _allGames.isNotEmpty && !_isFetching) {
      debugPrint(
        '[SearchGames] Skipping duplicate search for "$trimmedQuery" - already have ${_allGames.length} games',
      );
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

      // Deduplicate players by name but keep the best match for the query
      // (exact/prefix match first, then rating + FIDE id for tie-breaks).
      final playersByName = <String, _ScoredPlayerResult>{};
      for (final result in searchResults.playerResults) {
        final player = result.player;
        if (player == null) continue;

        final score = _playerMatchScore(player.name, query);
        final candidate = _ScoredPlayerResult(
          result: result,
          matchScore: score,
        );
        final key = player.name.toLowerCase();
        final existing = playersByName[key];

        if (existing == null || candidate.isBetterThan(existing)) {
          playersByName[key] = candidate;
        }
      }

      // Sort deduplicated players by how well they match the query, then rating.
      final uniquePlayerResults =
          playersByName.values.toList()..sort((a, b) {
            if (a.matchScore != b.matchScore) {
              return b.matchScore.compareTo(a.matchScore);
            }

            final aRating = a.result.player?.rating ?? 0;
            final bRating = b.result.player?.rating ?? 0;
            if (aRating != bRating) {
              return bRating.compareTo(aRating);
            }

            final aHasFide = a.result.player?.fideId != null;
            final bHasFide = b.result.player?.fideId != null;
            if (aHasFide != bHasFide) {
              return aHasFide ? -1 : 1;
            }

            return a.result.player!.name.compareTo(b.result.player!.name);
          });

      final topPlayers = uniquePlayerResults.take(_maxPlayers).toList();

      debugPrint(
        '[SearchGames] Found ${topPlayers.length} unique top players for "$query"',
      );
      for (final candidate in topPlayers) {
        final player = candidate.result.player!;
        debugPrint(
          '[SearchGames] - ${player.name} (matchScore: ${candidate.matchScore}, ELO: ${player.rating}, FIDE: ${player.fideId})',
        );
      }

      if (topPlayers.isEmpty) {
        // Fallback: try pulling games by country if available
        final fallbackFed = searchResults.countryFedCode;
        if (fallbackFed != null && fallbackFed.isNotEmpty) {
          try {
            final countryGames = await gameRepository
                .getGamesByCountryCodePaginated(
                  countryCode: fallbackFed,
                  limit: _countryFallbackLimit,
                );
            if (countryGames.isNotEmpty) {
              _allGames.addAll(countryGames);
              _sortAndDedupGames();
              state = AsyncValue.data(List<Games>.from(_allGames));
              _isFetching = false;
              return;
            }
          } catch (e) {
            debugPrint('[SearchGames] Country fallback failed: $e');
          }
        }

        state = const AsyncValue.data([]);
        _isFetching = false;
        return;
      }

      // Fetch ALL games for the best-matching player (preferring query match, then ELO)
      // No limit applied - ensures we get all tournaments where this player participated
      final allGames = <Games>[];
      final topPlayer = topPlayers.first.result.player!;

      try {
        List<Games> games;
        if (topPlayer.fideId != null) {
          // Use FIDE ID if available (more reliable)
          // No limit - fetch ALL games to ensure all events are captured
          games = await gameRepository.getGamesByFideId(
            topPlayer.fideId.toString(),
          );
          debugPrint(
            '[SearchGames] Fetched ${games.length} games for ${topPlayer.name} by FIDE ID ${topPlayer.fideId}',
          );
        } else {
          // Fallback to player name - no limit
          games = await gameRepository.getGamesByPlayerName(topPlayer.name);
          debugPrint(
            '[SearchGames] Fetched ${games.length} games for ${topPlayer.name} by name',
          );
        }
        allGames.addAll(games);
      } catch (e) {
        debugPrint(
          '[SearchGames] Error fetching games for ${topPlayer.name}: $e',
        );
      }

      _allGames.addAll(allGames);

      // If no games found for top player, try country fallback using player fed or search hint
      if (_allGames.isEmpty) {
        final fallbackFed =
            topPlayer.fed?.toUpperCase() ?? searchResults.countryFedCode;
        if (fallbackFed != null && fallbackFed.isNotEmpty) {
          try {
            final countryGames = await gameRepository
                .getGamesByCountryCodePaginated(
                  countryCode: fallbackFed,
                  limit: _countryFallbackLimit,
                );
            _allGames.addAll(countryGames);
          } catch (e) {
            debugPrint(
              '[SearchGames] Country fallback (player-fed) failed: $e',
            );
          }
        }
      }

      _sortAndDedupGames();
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

  void _sortAndDedupGames() {
    // Deduplicate first
    final uniqueGames = <String, Games>{};
    for (final game in _allGames) {
      uniqueGames[game.id] = game;
    }
    _allGames
      ..clear()
      ..addAll(uniqueGames.values);

    // Sort games with proper relevance:
    // 1. Live games first (status == '*')
    // 2. Most recent activity first (lastMoveTime descending)
    _allGames.sort((a, b) {
      // 1. Live games first
      final aLive = a.status == '*';
      final bLive = b.status == '*';
      if (aLive != bLive) return aLive ? -1 : 1;

      // 2. Sort by last move time (most recent first)
      final aTime = a.lastMoveTime;
      final bTime = b.lastMoveTime;
      if (aTime != null && bTime != null) {
        return bTime.compareTo(aTime); // Descending - most recent first
      } else if (aTime != null) {
        return -1;
      } else if (bTime != null) {
        return 1;
      }

      return 0;
    });
  }

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
    this.tournamentDate,
  });

  final String tourId;
  String tourName;
  final List<Games> games;
  bool hasLiveGames;
  final DateTime? tournamentDate;
}

/// Internal wrapper to keep match score alongside the search result for ranking.
class _ScoredPlayerResult {
  const _ScoredPlayerResult({required this.result, required this.matchScore});

  final SearchResult result;
  final int matchScore;

  bool isBetterThan(_ScoredPlayerResult other) {
    if (matchScore != other.matchScore) {
      return matchScore > other.matchScore;
    }

    final rating = result.player?.rating ?? 0;
    final otherRating = other.result.player?.rating ?? 0;
    if (rating != otherRating) {
      return rating > otherRating;
    }

    final hasFideId = result.player?.fideId != null;
    final otherHasFideId = other.result.player?.fideId != null;
    if (hasFideId != otherHasFideId) {
      return hasFideId;
    }

    return result.player!.name.compareTo(other.result.player!.name) < 0;
  }
}

int _playerMatchScore(String playerName, String query) {
  String normalize(String value) =>
      value
          .toLowerCase()
          .replaceAll(',', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

  final normalizedQuery = normalize(query);
  if (normalizedQuery.isEmpty) return 0;

  final normalizedName = normalize(playerName);

  // Perfect / near-perfect matches first
  if (normalizedName == normalizedQuery) return 120;
  if (normalizedName.startsWith(normalizedQuery) ||
      normalizedQuery.startsWith(normalizedName)) {
    return 110;
  }

  final nameWords =
      normalizedName.split(' ').where((word) => word.isNotEmpty).toList();
  final queryWords =
      normalizedQuery.split(' ').where((word) => word.isNotEmpty).toList();

  int prefixMatches = 0;
  for (final qw in queryWords) {
    if (nameWords.any((nw) => nw.startsWith(qw) || qw.startsWith(nw))) {
      prefixMatches++;
    }
  }

  if (prefixMatches == queryWords.length && queryWords.isNotEmpty) {
    return 105; // All query words match (order-flexible)
  }

  if (prefixMatches > 0) {
    final coverage = prefixMatches / queryWords.length;
    return (80 + (coverage * 20)).round(); // 80-100 depending on coverage
  }

  // Soft fallback for partial contains to avoid dropping near-misses completely
  final hasPartial = queryWords.any(
    (qw) => nameWords.any((nw) => nw.contains(qw) || qw.contains(nw)),
  );
  if (hasPartial) return 65;

  return 40; // weak match
}
