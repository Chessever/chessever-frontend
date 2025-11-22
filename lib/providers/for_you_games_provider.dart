import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============================================================================
// PROVIDER DEFINITIONS
// ============================================================================

/// Main provider for For You games - fetches and sorts personalized games
final forYouGamesProvider = StateNotifierProvider.autoDispose<
    ForYouGamesNotifier, AsyncValue<List<Games>>>(
  (ref) => ForYouGamesNotifier(ref),
);

/// Provider for grouped games (by tournament) for UI display
final groupedForYouGamesProvider = Provider.autoDispose<List<GroupedTournamentGames>>((ref) {
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];

  final grouped = <String, GroupedTournamentGames>{};

  for (final game in games) {
    final tourId = game.tourId ?? 'unknown';
    final tourName = game.tourSlug ?? 'Unknown Tournament';

    if (!grouped.containsKey(tourId)) {
      grouped[tourId] = GroupedTournamentGames(
        tourId: tourId,
        tourName: tourName,
        games: [],
        hasLiveGames: false,
      );
    }

    grouped[tourId]!.games.add(game);
    if (game.status == '*') {
      grouped[tourId]!.hasLiveGames = true;
    }
  }

  return grouped.values.toList()
    ..sort((a, b) {
      // Sort groups: live games first, then by size
      if (a.hasLiveGames && !b.hasLiveGames) return -1;
      if (!a.hasLiveGames && b.hasLiveGames) return 1;
      return b.games.length.compareTo(a.games.length);
    });
});

/// Provider for converted games (Games to GamesTourModel)
final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>((ref) {
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];

  return games.map((game) => GamesTourModel.fromGame(game)).toList();
});

// ============================================================================
// STATE NOTIFIER
// ============================================================================

/// Notifier for managing For You games state
///
/// Priority system (IMPORTANT):
/// 1. Favorited players' games (highest priority, live games first within category)
/// 2. Favorited events' games (live games first within category)
/// 3. Countryman games (ELO ≥ 2300, live games first, then by ELO)
/// 4. High ELO games (ELO ≥ 2500, live games first, then by ELO)
///
/// Within each priority level, LIVE games always come before finished games.
/// But a finished game from a higher priority ALWAYS beats a live game from lower priority.
class ForYouGamesNotifier extends StateNotifier<AsyncValue<List<Games>>> {
  ForYouGamesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _initialize();
  }

  final Ref _ref;
  final List<Games> _allGames = [];
  bool _hasMore = true;
  bool _isFetchingMore = false;
  static const int _pageSize = 20;

  Future<void> _initialize() async {
    await loadGames();
  }

  /// Load initial games
  Future<void> loadGames() async {
    try {
      state = const AsyncValue.loading();
      _allGames.clear();
      _hasMore = true;

      await _fetchGames(offset: 0);

      state = AsyncValue.data(List<Games>.from(_allGames));
    } catch (e, stack) {
      debugPrint('[ForYouGames] Error loading games: $e');
      state = AsyncValue.error(e, stack);
    }
  }

  /// Load more games for infinite scroll
  Future<void> loadMore() async {
    if (_isFetchingMore || !_hasMore) return;

    try {
      _isFetchingMore = true;
      final currentLength = _allGames.length;

      await _fetchGames(offset: currentLength);

      state = AsyncValue.data(List<Games>.from(_allGames));
    } catch (e) {
      debugPrint('[ForYouGames] Error loading more: $e');
    } finally {
      _isFetchingMore = false;
    }
  }

  /// Fetch games from repository based on user preferences
  ///
  /// This method fetches games from different sources in priority order:
  /// 1. Favorited players' games
  /// 2. Favorited events' games
  /// 3. Countryman games (with ELO filter)
  /// 4. High ELO games as fallback
  Future<void> _fetchGames({required int offset}) async {
    final repository = _ref.read(gameRepositoryProvider);

    // Get user preferences
    final favoritesAsync = _ref.read(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];

    final favoriteEventsAsync = _ref.read(favoriteEventsProvider);
    final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];

    final countryState = _ref.read(countryDropdownProvider);
    final selectedCountry = countryState.value;

    debugPrint('[ForYouGames] === Fetching games (offset: $offset) ===');
    debugPrint('[ForYouGames] Favorites: ${favorites.length}');
    debugPrint('[ForYouGames] Favorite events: ${favoriteEvents.length}');
    debugPrint('[ForYouGames] Country: ${selectedCountry?.countryCode}');

    final newGames = <Games>[];

    // === PRIORITY 1: Favorited players' games ===
    // Fetch games for all favorited players
    // (Live games within this category are prioritized in sorting)
    if (favorites.isNotEmpty) {
      final fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId!)
          .toList();

      debugPrint('[ForYouGames] Fetching games for ${fideIds.length} favorited players');

      if (fideIds.isNotEmpty) {
        try {
          final favPlayerGames = await repository.getGamesByMultipleFideIds(
            fideIds: fideIds,
            limit: _pageSize,
            offset: offset,
          );
          newGames.addAll(favPlayerGames);
          debugPrint('[ForYouGames] Fetched ${favPlayerGames.length} favorited player games');
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching favorited player games: $e');
        }
      }

      // Also fetch games by player names (for players without FIDE IDs)
      final playerNames = favorites
          .where((f) => f.fideId == null || f.fideId!.isEmpty)
          .map((f) => f.playerName)
          .toList();

      for (final name in playerNames) {
        try {
          final nameGames = await repository.getGamesByPlayerName(
            name,
            limit: _pageSize ~/ playerNames.length.clamp(1, 10),
          );
          newGames.addAll(nameGames);
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching games for player $name: $e');
        }
      }
    }

    // === PRIORITY 2: Favorited events' games ===
    // Fetch games from favorited tournaments
    // (Live games within this category are prioritized in sorting)
    if (favoriteEvents.isNotEmpty) {
      final eventIds = favoriteEvents.map((e) => e.eventId).toList();

      debugPrint('[ForYouGames] Fetching games for ${eventIds.length} favorited events');

      // First try to get live games from favorited events
      try {
        final liveEventGames = await repository.getLiveGamesForEvents(
          eventIds: eventIds,
          limit: _pageSize ~/ 2,
        );
        newGames.addAll(liveEventGames);
        debugPrint('[ForYouGames] Fetched ${liveEventGames.length} live games from favorited events');
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching live event games: $e');
      }

      // Then get regular games from favorited events
      for (final eventId in eventIds.take(3)) { // Limit to avoid too many queries
        try {
          final eventGames = await repository.getGamesByTourId(
            eventId,
            limit: _pageSize ~/ eventIds.length.clamp(1, 5),
          );
          newGames.addAll(eventGames);
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching games for event $eventId: $e');
        }
      }
    }

    // === PRIORITY 3: Countryman games ===
    // Only games where at least one player from the country has ELO ≥ 2300
    // (Live games within this category are prioritized in sorting)
    if (selectedCountry != null && selectedCountry.countryCode.isNotEmpty) {
      try {
        final countryGames = await repository.getCountrymanGamesWithMinElo(
          countryCode: selectedCountry.countryCode,
          minElo: 2300, // Only show countryman games with ELO > 2300
          limit: _pageSize ~/ 2,
          offset: offset,
        );
        newGames.addAll(countryGames);
        debugPrint('[ForYouGames] Fetched ${countryGames.length} countryman games (ELO > 2300)');
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching countryman games: $e');
      }
    }

    // === PRIORITY 4: High ELO games (fallback) ===
    // Only games where at least one player has ELO >= 2500
    // (Live games within this category are prioritized in sorting)
    try {
      final highEloGames = await repository.getHighEloGames(
        minElo: 2500, // Only show games with 2500+ ELO players
        limit: _pageSize ~/ 2, // Smaller batch since this is lower priority
        offset: offset,
      );
      newGames.addAll(highEloGames);
      debugPrint('[ForYouGames] Fetched ${highEloGames.length} high ELO (2500+) games');
    } catch (e) {
      debugPrint('[ForYouGames] Error fetching high ELO games: $e');
    }

    // Remove duplicates by game ID
    final gameIds = _allGames.map((g) => g.id).toSet();
    final uniqueNewGames = newGames.where((g) => !gameIds.contains(g.id)).toList();

    if (uniqueNewGames.isNotEmpty) {
      _allGames.addAll(uniqueNewGames);

      // Sort games with heterogeneous distribution
      final favoriteEventIds = favoriteEvents
          .map((e) => e.eventId)
          .where((id) => id.isNotEmpty)
          .toSet();

      _sortGames(favorites, selectedCountry?.countryCode, favoriteEventIds);
    }

    // Check if we have more
    _hasMore = uniqueNewGames.isNotEmpty;
    debugPrint('[ForYouGames] Has more: $_hasMore, Total games: ${_allGames.length}');
  }

  /// Sort games with heterogeneous distribution while respecting priority
  ///
  /// Creates a weighted scoring system that:
  /// 1. Respects category priority (favorite players > events > countryman > high ELO)
  /// 2. Prioritizes live games within each category
  /// 3. Creates variety by interleaving different categories
  /// 4. Ensures finished games from higher categories appear before lower categories
  void _sortGames(List favorites, String? countryCode, Set<String> favoriteEventIds) {
    if (_allGames.isEmpty) return;

    debugPrint('[ForYouGames] Creating heterogeneous distribution for ${_allGames.length} games...');

    // Create lookup sets for performance
    final Set<String> favoritedFideIds = favorites
        .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
        .map((f) => f.fideId as String)
        .toSet();

    final Set<String> favoritedNames = favorites
        .map((f) => f.playerName as String)
        .map((name) => name.toLowerCase())
        .toSet();

    // Score and categorize all games
    final List<_ScoredGame> scoredGames = [];

    for (final game in _allGames) {
      double score = 0.0;
      String category = '';

      // Check game categories
      final hasFavorite = _hasFavoritedPlayer(game, favoritedFideIds, favoritedNames);
      final hasEvent = favoriteEventIds.contains(game.tourId);
      final hasCountryman = countryCode != null && _hasPlayerFromCountry(game, countryCode);
      final maxElo = _getMaxElo(game);
      final isLive = _isLiveGame(game);

      // Assign scores based on priority (higher score = higher priority)
      if (hasFavorite) {
        score = 10000.0; // Base score for favorite players
        category = 'favorite_player';
        if (isLive) score += 5000.0; // Live bonus
      } else if (hasEvent) {
        score = 7000.0; // Base score for favorite events
        category = 'favorite_event';
        if (isLive) score += 3500.0; // Live bonus
      } else if (hasCountryman && maxElo >= 2300) {
        score = 4000.0; // Base score for countryman
        category = 'countryman';
        if (isLive) score += 2000.0; // Live bonus
        score += maxElo * 0.1; // ELO bonus
      } else if (maxElo >= 2500) {
        score = 1000.0; // Base score for high ELO
        category = 'high_elo';
        if (isLive) score += 500.0; // Live bonus
        score += maxElo * 0.05; // ELO bonus
      } else {
        continue; // Skip games that don't match any category
      }

      // Add recency bonus
      if (game.lastMoveTime != null) {
        final minutesAgo = DateTime.now().difference(game.lastMoveTime!).inMinutes;
        if (minutesAgo < 60) {
          score += (60 - minutesAgo) * 1.5; // Up to 90 points for recent games
        }
      }

      scoredGames.add(_ScoredGame(
        game: game,
        score: score,
        category: category,
        isLive: isLive,
        maxElo: maxElo,
      ));
    }

    // Sort by score
    scoredGames.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      return _compareByLastMoveTime(a.game, b.game);
    });

    // Apply heterogeneous distribution
    final distributed = _applyHeterogeneousDistribution(scoredGames);

    // Update games list
    _allGames.clear();
    _allGames.addAll(distributed.map((sg) => sg.game));

    // Debug output
    if (distributed.isNotEmpty) {
      final categoryCounts = <String, int>{};
      for (final sg in distributed.take(20)) {
        categoryCounts[sg.category] = (categoryCounts[sg.category] ?? 0) + 1;
      }
      debugPrint('[ForYouGames] Top 20 games distribution: $categoryCounts');
    }
  }

  /// Apply heterogeneous distribution for variety while respecting priority
  List<_ScoredGame> _applyHeterogeneousDistribution(List<_ScoredGame> scoredGames) {
    if (scoredGames.length <= 3) return scoredGames;

    final result = <_ScoredGame>[];
    final remaining = List<_ScoredGame>.from(scoredGames);
    final categoryLastIndex = <String, int>{};

    while (remaining.isNotEmpty) {
      _ScoredGame? bestCandidate;
      double bestAdjustedScore = -1;

      // Consider top candidates (not just first)
      final candidateCount = remaining.length.clamp(1, 10);

      for (int i = 0; i < candidateCount; i++) {
        final candidate = remaining[i];
        double adjustedScore = candidate.score;

        // Apply diversity penalty if we've seen this category recently
        final lastSeen = categoryLastIndex[candidate.category] ?? -10;
        final gamesSince = result.length - lastSeen;

        // Reduce score if same category appeared recently
        // But high-priority items can override this
        if (gamesSince < 4 && candidate.score < 15000) {
          adjustedScore *= (0.6 + gamesSince * 0.1);
        }

        // First item or ultra-high priority gets no penalty
        if (result.isEmpty || candidate.score > 15000) {
          adjustedScore = candidate.score;
        }

        if (adjustedScore > bestAdjustedScore) {
          bestAdjustedScore = adjustedScore;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate != null) {
        result.add(bestCandidate);
        categoryLastIndex[bestCandidate.category] = result.length - 1;
        remaining.remove(bestCandidate);
      } else {
        // Fallback: take first remaining
        result.add(remaining.removeAt(0));
      }
    }

    return result;
  }

  bool _isLiveGame(Games game) {
    return game.status == '*' || game.status == 'ongoing';
  }

  bool _hasFavoritedPlayer(
    Games game,
    Set<String> favoritedFideIds,
    Set<String> favoritedNames,
  ) {
    if (game.players == null) return false;

    for (final player in game.players!) {
      if (player.fideId > 0 && favoritedFideIds.contains(player.fideId.toString())) {
        return true;
      }
      if (favoritedNames.contains(player.name.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  bool _hasPlayerFromCountry(Games game, String countryCode) {
    if (game.players == null) return false;
    return game.players!.any((p) => p.fed.toUpperCase() == countryCode.toUpperCase());
  }

  int _getMaxElo(Games game) {
    if (game.players == null || game.players!.isEmpty) return 0;
    return game.players!.map((p) => p.rating).reduce((a, b) => a > b ? a : b);
  }

  int _compareByLastMoveTime(Games a, Games b) {
    if (a.lastMoveTime == null && b.lastMoveTime == null) return 0;
    if (a.lastMoveTime == null) return 1;
    if (b.lastMoveTime == null) return -1;
    return b.lastMoveTime!.compareTo(a.lastMoveTime!);
  }

  /// Refresh the feed
  Future<void> refresh() async {
    await loadGames();
  }

  bool get isFetchingMore => _isFetchingMore;
  bool get hasMore => _hasMore;
}

// ============================================================================
// MODELS
// ============================================================================

/// Represents games grouped by tournament for UI display
class GroupedTournamentGames {
  GroupedTournamentGames({
    required this.tourId,
    required this.tourName,
    required this.games,
    required this.hasLiveGames,
  });

  final String tourId;
  final String tourName;
  final List<Games> games;
  bool hasLiveGames;
}

/// Internal model for scoring games during sorting
class _ScoredGame {
  const _ScoredGame({
    required this.game,
    required this.score,
    required this.category,
    required this.isLive,
    required this.maxElo,
  });

  final Games game;
  final double score;
  final String category;
  final bool isLive;
  final int maxElo;
}

