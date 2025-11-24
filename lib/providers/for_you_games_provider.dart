import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============================================================================
// PROVIDER DEFINITIONS
// ============================================================================

/// Main provider for For You games - fetches and sorts personalized games
///
/// NOTE: Using keepAlive to prevent data loss when switching tabs.
/// This ensures consistent data and scroll position preservation.
final forYouGamesProvider = StateNotifierProvider.autoDispose<
    ForYouGamesNotifier, AsyncValue<List<Games>>>(
  (ref) {
    // CRITICAL: Keep provider alive during session to prevent:
    // 1. Data discrepancy when switching tabs
    // 2. Scroll position loss
    // 3. Re-animations
    ref.keepAlive();

    return ForYouGamesNotifier(ref);
  },
);

/// Provider for grouped games (by tournament) for UI display
final groupedForYouGamesProvider = Provider.autoDispose<List<GroupedTournamentGames>>((ref) {
  ref.keepAlive(); // Keep alive to match main provider
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];
  final initialGameIds = ref.read(forYouGamesProvider.notifier).initialGameIds;

  // CRITICAL: Separate initial games from pagination games to prevent scroll jumping
  // Initial games are grouped normally, pagination games are appended at the end
  final initialGames = <Games>[];
  final paginationGames = <Games>[];

  for (final game in games) {
    if (initialGameIds.contains(game.id)) {
      initialGames.add(game);
    } else {
      paginationGames.add(game);
    }
  }

  // Group only initial games (maintains scroll position stability)
  final grouped = <String, GroupedTournamentGames>{};
  final groupOrder = <String>[]; // Track insertion order

  for (final game in initialGames) {
    final tourId = game.tourId;
    final tourName = game.tourSlug;

    if (!grouped.containsKey(tourId)) {
      grouped[tourId] = GroupedTournamentGames(
        tourId: tourId,
        tourName: tourName,
        games: [],
        hasLiveGames: false,
      );
      groupOrder.add(tourId); // Remember order of first appearance
    }

    grouped[tourId]!.games.add(game);
    if (game.status == '*') {
      grouped[tourId]!.hasLiveGames = true;
    }
  }

  // Convert to list in order of first appearance
  final result = groupOrder.map((tourId) => grouped[tourId]!).toList();

  // Group pagination games separately and append at the end
  // This ensures new items are always added at the END, never in the middle
  if (paginationGames.isNotEmpty) {
    final paginationGrouped = <String, GroupedTournamentGames>{};
    final paginationOrder = <String>[];

    for (final game in paginationGames) {
      final tourId = game.tourId;
      final tourName = game.tourSlug;

      // Use a unique key for pagination groups to avoid key conflicts
      final paginationTourKey = '${tourId}_more';

      if (!paginationGrouped.containsKey(paginationTourKey)) {
        paginationGrouped[paginationTourKey] = GroupedTournamentGames(
          tourId: paginationTourKey, // Unique ID for pagination group
          tourName: tourName,
          games: [],
          hasLiveGames: false,
        );
        paginationOrder.add(paginationTourKey);
      }

      paginationGrouped[paginationTourKey]!.games.add(game);
      if (game.status == '*') {
        paginationGrouped[paginationTourKey]!.hasLiveGames = true;
      }
    }

    // Append pagination groups at the end
    result.addAll(paginationOrder.map((tourId) => paginationGrouped[tourId]!));
  }

  return result;
});

/// Provider for converted games (Games to GamesTourModel)
final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>((ref) {
  ref.keepAlive(); // Keep alive to match main provider
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];

  return games.map((game) => GamesTourModel.fromGame(game)).toList();
});

/// Global set to track which game IDs have been animated
/// This prevents re-animation when widgets rebuild or tab switches
final forYouAnimatedGameIds = <String>{};

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
  bool _isRefreshing = false;
  DateTime? _lastFetchAt;
  static const int _pageSize = 30; // Increased for better pagination
  int _emptyFetchCount = 0; // Track consecutive empty fetches
  int _favoritePlayersOffset = 0;
  final Map<String, int> _favoriteNameOffsets = {};
  final Map<String, int> _favoriteEventOffsets = {};
  int _countryOffset = 0;
  int _highEloOffset = 0;
  int _highEloLiveOffset = 0;

  /// Track whether initial load had preferences available
  /// This helps determine if we need to refresh when user visits the tab
  bool _initialLoadHadPreferences = false;

  /// Track game IDs from initial load to prevent scroll jumping on pagination
  /// Games added during pagination won't be inserted into existing groups
  final Set<String> _initialGameIds = {};

  Future<void> _initialize() async {
    await _waitForInitialPreferences();
    await loadGames();
  }

  Future<void> _waitForInitialPreferences() async {
    // Wait for favorites/events/country to resolve so first paint is personalized.
    final futures = <Future<void>>[
      _waitForFuture(() => _ref.read(favoritePlayersProviderNew.future)),
      _waitForFuture(() => _ref.read(favoriteEventsProvider.future)),
      _waitForCountrySelection(),
    ];

    await Future.wait(futures);
  }

  Future<void> _waitForFuture<T>(Future<T> Function() futureBuilder) async {
    try {
      await futureBuilder().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Ignore and continue with whatever data is available.
    }
  }

  Future<void> _waitForCountrySelection() async {
    final current = _ref.read(countryDropdownProvider);
    if (!current.isLoading) return;

    final completer = Completer<void>();
    final sub = _ref.listen<AsyncValue<Country>>(
      countryDropdownProvider,
      (_, next) {
        if (!next.isLoading && !completer.isCompleted) {
          completer.complete();
        }
      },
      fireImmediately: true,
    );

    try {
      await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    } finally {
      sub.close();
    }
  }

  void _resetPaginationState() {
    _allGames.clear();
    _initialGameIds.clear();
    _hasMore = true;
    _isFetchingMore = false;
    _emptyFetchCount = 0;
    _favoritePlayersOffset = 0;
    _favoriteNameOffsets.clear();
    _favoriteEventOffsets.clear();
    _countryOffset = 0;
    _highEloOffset = 0;
    _highEloLiveOffset = 0;
    _lastFetchAt = null;
  }

  /// Load initial games
  Future<void> loadGames({bool showLoading = true}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      if (showLoading) {
        state = const AsyncValue.loading();
      }
      _resetPaginationState();

      await _fetchGames(isInitialLoad: true);

      state = AsyncValue.data(List<Games>.from(_allGames));
    } catch (e, stack) {
      debugPrint('[ForYouGames] Error loading games: $e');
      state = AsyncValue.error(e, stack);
    } finally {
      _isRefreshing = false;
    }
  }

  /// Load more games for infinite scroll
  Future<void> loadMore() async {
    if (_isFetchingMore || !_hasMore || _isRefreshing) return;

    try {
      _isFetchingMore = true;
      await _fetchGames(isInitialLoad: false);

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
  Future<void> _fetchGames({required bool isInitialLoad}) async {
    final repository = _ref.read(gameRepositoryProvider);

    // Get user preferences
    final favoritesAsync = _ref.read(favoritePlayersProviderNew);
    final favorites = favoritesAsync.valueOrNull ?? [];

    final favoriteEventsAsync = _ref.read(favoriteEventsProvider);
    final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];

    final countryState = _ref.read(countryDropdownProvider);
    final selectedCountry = countryState.value;

    // Track if initial load has any preferences available
    if (isInitialLoad) {
      _initialLoadHadPreferences = favorites.isNotEmpty ||
          favoriteEvents.isNotEmpty ||
          (selectedCountry != null && selectedCountry.countryCode.isNotEmpty);
    }

    debugPrint('[ForYouGames] === Fetching games (page: ${_allGames.length}) ===');
    debugPrint('[ForYouGames] Favorites: ${favorites.length}');
    debugPrint('[ForYouGames] Favorite events: ${favoriteEvents.length}');
    debugPrint('[ForYouGames] Country: ${selectedCountry?.countryCode}');

    final newGames = <Games>[];
    final seenGameIds = _allGames.map((g) => g.id).toSet();

    // Helper to filter live games on loadMore and deduplicate within this fetch.
    void addUniqueGames(List<Games> games) {
      final filteredGames =
          isInitialLoad ? games : games.where((g) => g.status != '*');

      for (final game in filteredGames) {
        if (seenGameIds.add(game.id)) {
          newGames.add(game);
        }
      }
    }

    // === LIVE GAMES (absolute priority, but only relevant sources) ===
    if (isInitialLoad) {
      // Live games for favorited players
      final fideIds = favorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId!)
          .toList();
      if (fideIds.isNotEmpty) {
        try {
          final liveFavPlayers = await repository.getLiveGamesForPlayers(
            fideIds: fideIds,
            limit: _pageSize,
          );
          addUniqueGames(liveFavPlayers);
          debugPrint('[ForYouGames] Fetched ${liveFavPlayers.length} LIVE games for favorited players');
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching live games for favorites: $e');
        }
      }

      // Live games from favorited events
      if (favoriteEvents.isNotEmpty) {
        try {
          final liveEventGames = await repository.getLiveGamesForEvents(
            eventIds: favoriteEvents.map((e) => e.eventId).toList(),
            limit: _pageSize,
          );
          addUniqueGames(liveEventGames);
          debugPrint('[ForYouGames] Fetched ${liveEventGames.length} LIVE games from favorited events');
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching live event games: $e');
        }
      }

      // Live high-ELO games (fallback, least priority but still relevant)
      try {
        final liveHighElo = await repository.getHighEloGames(
          minElo: 2500,
          limit: _pageSize,
          offset: _highEloLiveOffset,
          onlyLive: true,
        );
        // keep offset in sync with multiplier inside repo when live-only
        _highEloLiveOffset += _pageSize * 2;
        addUniqueGames(liveHighElo);
        debugPrint('[ForYouGames] Fetched ${liveHighElo.length} LIVE high ELO games');
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching live high ELO games: $e');
      }
    }

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
          final favPlayerLimit = _pageSize * 2;
          final favPlayerGames = await repository.getGamesByMultipleFideIds(
            fideIds: fideIds,
            limit: favPlayerLimit, // Fetch more to compensate for filtering
            offset: _favoritePlayersOffset,
          );
          _favoritePlayersOffset += favPlayerLimit;
          addUniqueGames(favPlayerGames);
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
          final perNameLimit = (_pageSize ~/ playerNames.length.clamp(1, 5));
          final limit = perNameLimit > 0 ? perNameLimit : 1;
          final offsetForName = _favoriteNameOffsets[name] ?? 0;
          final nameGames = await repository.getGamesByPlayerName(
            name,
            limit: limit,
            offset: offsetForName,
          );
          _favoriteNameOffsets[name] = offsetForName + limit;
          addUniqueGames(nameGames);
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

      // Then get regular games from favorited events
      for (final eventId in eventIds.take(3)) { // Limit to avoid too many queries
        try {
          final perEventLimit = (_pageSize ~/ eventIds.length.clamp(1, 5));
          final limit = perEventLimit > 0 ? perEventLimit : _pageSize;
          final offsetForEvent = _favoriteEventOffsets[eventId] ?? 0;
          final eventGames = await repository.getGamesByTourId(
            eventId,
            limit: limit,
            offset: offsetForEvent,
          );
          _favoriteEventOffsets[eventId] = offsetForEvent + limit;
          addUniqueGames(eventGames);
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
        final countryLimit = _pageSize;
        final countryGames = await repository.getCountrymanGamesWithMinElo(
          countryCode: selectedCountry.countryCode,
          minElo: 2300, // Only show countryman games with ELO > 2300
          limit: countryLimit, // Increased from _pageSize ~/ 2
          offset: _countryOffset,
        );
        _countryOffset += countryLimit * 2; // Matches the multiplier used in the query
        addUniqueGames(countryGames);
        debugPrint('[ForYouGames] Fetched ${countryGames.length} countryman games (ELO > 2300)');
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching countryman games: $e');
      }
    }

    // === PRIORITY 4: High ELO games (fallback) ===
    // Only games where at least one player has ELO >= 2500
    // (Live games within this category are prioritized in sorting)
    try {
      final highEloLimit = _pageSize;
      final highEloGames = await repository.getHighEloGames(
        minElo: 2500, // Only show games with 2500+ ELO players
        limit: highEloLimit, // Increased from _pageSize ~/ 2 for better coverage
        offset: _highEloOffset,
      );
      // Keep offset in sync with the multiplier inside getHighEloGames (3x)
      _highEloOffset += highEloLimit * 3;
      addUniqueGames(highEloGames);
      debugPrint('[ForYouGames] Fetched ${highEloGames.length} high ELO (2500+) games');
    } catch (e) {
      debugPrint('[ForYouGames] Error fetching high ELO games: $e');
    }

    if (newGames.isNotEmpty) {
      _allGames.addAll(newGames);
      _emptyFetchCount = 0; // Reset empty fetch counter

      // CRITICAL: Only sort on initial load to prevent scroll position jumping
      // On pagination (loadMore), new items are already appended at the end
      if (isInitialLoad) {
        // Sort games with heterogeneous distribution
        final favoriteEventIds = favoriteEvents
            .map((e) => e.eventId)
            .where((id) => id.isNotEmpty)
            .toSet();

        _sortGames(favorites, selectedCountry?.countryCode, favoriteEventIds);

        // Track initial game IDs AFTER sorting to preserve grouping order
        _initialGameIds.addAll(_allGames.map((g) => g.id));
      }
    } else {
      _emptyFetchCount++;
      debugPrint('[ForYouGames] Empty fetch #$_emptyFetchCount');
    }

    // Check if we have more - allow up to 3 empty fetches before giving up
    // This handles cases where live games dominate the results
    _hasMore = _emptyFetchCount < 3;
    debugPrint('[ForYouGames] Has more: $_hasMore, Total games: ${_allGames.length}, Empty fetches: $_emptyFetchCount');

    // Track last successful fetch to detect stale data when revisiting the tab
    _lastFetchAt = DateTime.now();
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

    // Sort live and non-live separately to keep all live games at the very top.
    final liveGames = scoredGames.where((sg) => sg.isLive).toList();
    final nonLiveGames = scoredGames.where((sg) => !sg.isLive).toList();

    _sortScoredGames(liveGames, prioritizeElo: true);
    _sortScoredGames(nonLiveGames);

    // Pin the highest-ELO non-live game(s) just after live games
    final int? topEloInt =
        nonLiveGames.isEmpty ? null : nonLiveGames.map((g) => g.maxElo).reduce((a, b) => a > b ? a : b);
    final double topElo = (topEloInt ?? 0).toDouble();
    final pinnedHighElo = <_ScoredGame>[];
    if (topElo > 0) {
      pinnedHighElo.addAll(nonLiveGames.where((g) => g.maxElo == topElo));
      nonLiveGames.removeWhere((g) => g.maxElo == topElo);
    }

    // Apply heterogeneous distribution only to non-live games (keeps existing logic)
    final distributedNonLive = _applyHeterogeneousDistribution(nonLiveGames);

    // Final ordering: all live games first (sorted), then highest-ELO game(s), then the distributed non-live list
    final distributed = [...liveGames, ...pinnedHighElo, ...distributedNonLive];

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

  /// Sort helper: by score, then recency
  void _sortScoredGames(List<_ScoredGame> games, {bool prioritizeElo = false}) {
    games.sort((a, b) {
      if (prioritizeElo) {
        final eloDiff = b.maxElo.compareTo(a.maxElo);
        if (eloDiff != 0) return eloDiff;
      }

      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      return _compareByLastMoveTime(a.game, b.game);
    });
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
    await loadGames(showLoading: false);
  }

  /// Refresh only when data is considered stale (e.g., when re-opening the tab)
  /// Also refreshes if initial load didn't have preferences but they're available now
  Future<void> refreshIfStale({Duration maxAge = const Duration(seconds: 60)}) async {
    if (state.isLoading || _isFetchingMore || _isRefreshing) return;

    // Check if preferences are now available but weren't during initial load
    if (!_initialLoadHadPreferences) {
      final favoritesAsync = _ref.read(favoritePlayersProviderNew);
      final favorites = favoritesAsync.valueOrNull ?? [];

      final favoriteEventsAsync = _ref.read(favoriteEventsProvider);
      final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];

      final countryState = _ref.read(countryDropdownProvider);
      final selectedCountry = countryState.value;

      final hasPreferencesNow = favorites.isNotEmpty ||
          favoriteEvents.isNotEmpty ||
          (selectedCountry != null && selectedCountry.countryCode.isNotEmpty);

      if (hasPreferencesNow) {
        debugPrint('[ForYouGames] Preferences now available, refreshing...');
        await refresh();
        return;
      }
    }

    if (_lastFetchAt != null &&
        DateTime.now().difference(_lastFetchAt!) <= maxAge) {
      return;
    }

    await refresh();
  }

  bool get isFetchingMore => _isFetchingMore;
  bool get hasMore => _hasMore;

  /// Get the set of game IDs from initial load (for scroll position stability)
  Set<String> get initialGameIds => _initialGameIds;
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
