import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/country_utils.dart';
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
  ForYouGamesNotifier,
  AsyncValue<List<Games>>
>((ref) {
  // CRITICAL: Keep provider alive during session to prevent:
  // 1. Data discrepancy when switching tabs
  // 2. Scroll position loss
  // 3. Re-animations
  ref.keepAlive();

  return ForYouGamesNotifier(ref);
});

/// Provider for grouped games (by tournament) for UI display
final groupedForYouGamesProvider = Provider.autoDispose<
  List<GroupedTournamentGames>
>((ref) {
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
        groupKey: tourId,
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
          groupKey: paginationTourKey, // Unique grouping key
          tourId: tourId, // Keep original tour ID for data fetch
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
final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>(
  (ref) {
    ref.keepAlive(); // Keep alive to match main provider
    final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];

    return games.map((game) => GamesTourModel.fromGame(game)).toList();
  },
);

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
/// 4. High ELO games (ELO ≥ 2600, live games first, then by ELO; injected rarely)
///
/// Within each priority level, LIVE games always come before finished games.
/// But a finished game from a higher priority ALWAYS beats a live game from lower priority.
///
/// STANDARD: Each tournament displays exactly 4 games. If there aren't enough
/// personalized games, we fill up with top board games (highest ELO players).
class ForYouGamesNotifier extends StateNotifier<AsyncValue<List<Games>>> {
  ForYouGamesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _setupPreferenceListeners();
    _initialize();
  }

  final Ref _ref;
  final List<Games> _allGames = [];
  bool _hasMore = true;
  bool _isFetchingMore = false;
  bool _isRefreshing = false;
  DateTime? _lastFetchAt;
  static const int _pageSize = 30; // Increased for better pagination

  /// Minimum number of games to show per tournament in the For You feed
  /// (tournaments may have more if the algorithm's criteria bring more games)
  static const int _gamesPerTournament = 4;
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
  Timer? _preferenceRefreshDebounce;

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
    final sub = _ref.listen<AsyncValue<Country>>(countryDropdownProvider, (
      _,
      next,
    ) {
      if (!next.isLoading && !completer.isCompleted) {
        completer.complete();
      }
    }, fireImmediately: true);

    try {
      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
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

  void _setupPreferenceListeners() {
    // Any change in favorites/country should trigger a recompute of the feed.
    void scheduleRefresh() {
      _preferenceRefreshDebounce?.cancel();
      _preferenceRefreshDebounce = Timer(
        const Duration(milliseconds: 400),
        () => refresh(),
      );
    }

    _ref.listen(
      favoritePlayersProviderNew,
      (_, __) => scheduleRefresh(),
      fireImmediately: false,
    );
    _ref.listen(
      favoriteEventsProvider,
      (_, __) => scheduleRefresh(),
      fireImmediately: false,
    );
    _ref.listen(
      countryDropdownProvider,
      (_, __) => scheduleRefresh(),
      fireImmediately: false,
    );
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

      // STANDARD: Enforce exactly 4 games per tournament
      // Fill up tournaments with fewer than 4 games using top board games
      await _enforceGamesPerTournamentStandard();

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
      _initialLoadHadPreferences =
          favorites.isNotEmpty ||
          favoriteEvents.isNotEmpty ||
          (selectedCountry != null && selectedCountry.countryCode.isNotEmpty);
    }

    debugPrint(
      '[ForYouGames] === Fetching games (page: ${_allGames.length}) ===',
    );
    debugPrint('[ForYouGames] Favorites: ${favorites.length}');
    debugPrint('[ForYouGames] Favorite events: ${favoriteEvents.length}');
    debugPrint('[ForYouGames] Country: ${selectedCountry?.countryCode}');

    final newGames = <Games>[];
    final seenGameIds = _allGames.map((g) => g.id).toSet();

    // Helper to filter live games on loadMore, drop future (not-started) games,
    // and deduplicate within this fetch.
    void addUniqueGames(List<Games> games) {
      final filteredGames = (isInitialLoad
              ? games
              : games.where((g) => g.status != '*'))
          .where((g) => !_isFutureGame(g));

      for (final game in filteredGames) {
        if (seenGameIds.add(game.id)) {
          newGames.add(game);
        }
      }
    }

    // === LIVE GAMES (absolute priority, but only relevant sources) ===
    if (isInitialLoad) {
      // Live games for favorited players
      final fideIds =
          favorites
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
          debugPrint(
            '[ForYouGames] Fetched ${liveFavPlayers.length} LIVE games for favorited players',
          );
        } catch (e) {
          debugPrint(
            '[ForYouGames] Error fetching live games for favorites: $e',
          );
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
          debugPrint(
            '[ForYouGames] Fetched ${liveEventGames.length} LIVE games from favorited events',
          );
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching live event games: $e');
        }
      }

      // Live high-ELO games (fallback, least priority but still relevant)
      try {
        final liveHighElo = await repository.getHighEloGames(
          minElo: 2600,
          limit: _pageSize,
          offset: _highEloLiveOffset,
          onlyLive: true,
        );
        // keep offset in sync with multiplier inside repo when live-only
        _highEloLiveOffset += _pageSize * 2;
        addUniqueGames(liveHighElo);
        debugPrint(
          '[ForYouGames] Fetched ${liveHighElo.length} LIVE high ELO games',
        );
      } catch (e) {
        debugPrint('[ForYouGames] Error fetching live high ELO games: $e');
      }
    }

    // === PRIORITY 1: Favorited players' games ===
    // Fetch games for all favorited players
    // (Live games within this category are prioritized in sorting)
    if (favorites.isNotEmpty) {
      final fideIds =
          favorites
              .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
              .map((f) => f.fideId!)
              .toList();

      debugPrint(
        '[ForYouGames] Fetching games for ${fideIds.length} favorited players',
      );

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
          debugPrint(
            '[ForYouGames] Fetched ${favPlayerGames.length} favorited player games',
          );
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching favorited player games: $e');
        }
      }

      // Also fetch games by player names (for players without FIDE IDs)
      final playerNames =
          favorites
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

      debugPrint(
        '[ForYouGames] Fetching games for ${eventIds.length} favorited events',
      );

      // Then get regular games from favorited events
      for (final eventId in eventIds.take(3)) {
        // Limit to avoid too many queries
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
          debugPrint(
            '[ForYouGames] Error fetching games for event $eventId: $e',
          );
        }
      }
    }

    // === PRIORITY 3: Countryman games ===
    // Only games where at least one player from the country has ELO ≥ 2300
    // (Live games within this category are prioritized in sorting)
    if (selectedCountry != null && selectedCountry.countryCode.isNotEmpty) {
      try {
        final countryLimit = _pageSize;
        // Convert ISO 2-letter code (TR) to FIDE 3-letter code (TUR)
        final fideCode = CountryUtils.toFideCode(selectedCountry.countryCode);
        final countryGames = await repository.getCountrymanGamesWithMinElo(
          countryCode: fideCode,
          minElo: 2300, // Only show countryman games with ELO > 2300
          limit: countryLimit, // Increased from _pageSize ~/ 2
          offset: _countryOffset,
        );
        _countryOffset +=
            countryLimit * 2; // Matches the multiplier used in the query
        addUniqueGames(countryGames);
        debugPrint(
          '[ForYouGames] Fetched ${countryGames.length} countryman games (ELO > 2300)',
        );
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
        minElo: 2600, // Only show games with 2600+ ELO players
        limit:
            highEloLimit, // Increased from _pageSize ~/ 2 for better coverage
        offset: _highEloOffset,
      );
      // Keep offset in sync with the multiplier inside getHighEloGames (3x)
      _highEloOffset += highEloLimit * 3;
      addUniqueGames(highEloGames);
      debugPrint(
        '[ForYouGames] Fetched ${highEloGames.length} high ELO (2500+) games',
      );
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
        final favoriteEventIds =
            favoriteEvents
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
    debugPrint(
      '[ForYouGames] Has more: $_hasMore, Total games: ${_allGames.length}, Empty fetches: $_emptyFetchCount',
    );

    // Track last successful fetch to detect stale data when revisiting the tab
    _lastFetchAt = DateTime.now();
  }

  /// Enforces the standard of at least 4 games per tournament
  ///
  /// For each tournament in the feed:
  /// - If it has 4 or more games, keep all of them (don't limit the algorithm's natural selection)
  /// - If it has fewer than 4 games, fill up with top board games (highest ELO)
  Future<void> _enforceGamesPerTournamentStandard() async {
    if (_allGames.isEmpty) return;

    debugPrint('[ForYouGames] Enforcing $_gamesPerTournament games per tournament standard...');

    final repository = _ref.read(gameRepositoryProvider);

    // Group games by tournament, maintaining order of first appearance
    final Map<String, List<Games>> gamesByTour = {};
    final List<String> tourOrder = [];

    for (final game in _allGames) {
      final tourId = game.tourId;
      if (!gamesByTour.containsKey(tourId)) {
        gamesByTour[tourId] = [];
        tourOrder.add(tourId);
      }
      gamesByTour[tourId]!.add(game);
    }

    debugPrint('[ForYouGames] Found ${tourOrder.length} tournaments in feed');

    // Process each tournament
    final Set<String> allExistingGameIds = _allGames.map((g) => g.id).toSet();
    final List<Games> standardizedGames = [];

    for (final tourId in tourOrder) {
      final tourGames = gamesByTour[tourId]!;
      final currentCount = tourGames.length;

      if (currentCount >= _gamesPerTournament) {
        // Keep all games - don't limit the algorithm's natural selection
        // (favorite players, favorite events, countrymen, high elo may bring more than minimum)
        standardizedGames.addAll(tourGames);
        debugPrint(
          '[ForYouGames] Tournament $tourId: keeping all $currentCount games (meets minimum)',
        );
      } else {
        // Need to fill up with top board games to reach minimum of $_gamesPerTournament
        final neededGames = _gamesPerTournament - currentCount;
        debugPrint(
          '[ForYouGames] Tournament $tourId: has $currentCount games, need $neededGames more to reach minimum',
        );

        // Add existing games first
        standardizedGames.addAll(tourGames);

        // Fetch top board games to fill up
        try {
          final topBoardGames = await repository.getTopBoardGamesByTourId(
            tourId: tourId,
            limit: neededGames,
            excludeGameIds: allExistingGameIds,
          );

          if (topBoardGames.isNotEmpty) {
            standardizedGames.addAll(topBoardGames);
            // Add to tracking set to avoid duplicates in future fills
            allExistingGameIds.addAll(topBoardGames.map((g) => g.id));
            debugPrint(
              '[ForYouGames] Tournament $tourId: filled with ${topBoardGames.length} top board games',
            );
          }
        } catch (e) {
          debugPrint('[ForYouGames] Error fetching top board games for $tourId: $e');
        }
      }
    }

    // Update the games list with standardized version
    _allGames
      ..clear()
      ..addAll(standardizedGames);

    // Update initial game IDs to include filled games
    _initialGameIds
      ..clear()
      ..addAll(_allGames.map((g) => g.id));

    debugPrint(
      '[ForYouGames] Standardization complete: ${_allGames.length} games across ${tourOrder.length} tournaments',
    );
  }

  /// Sort games with heterogeneous distribution while respecting priority
  ///
  /// Creates a weighted scoring system that:
  /// 1. Respects category priority (favorite players > events > countryman > high ELO)
  /// 2. Prioritizes live games within each category
  /// 3. Creates variety by interleaving different categories (weighted round robin)
  /// 4. Ensures finished games from higher categories appear before lower categories, but live games get an extra boost and are top-most
  void _sortGames(
    List favorites,
    String? countryCode,
    Set<String> favoriteEventIds,
  ) {
    if (_allGames.isEmpty) return;

    debugPrint(
      '[ForYouGames] Creating heterogeneous distribution for ${_allGames.length} games...',
    );

    // Create lookup sets for performance
    final Set<String> favoritedFideIds =
        favorites
            .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
            .map((f) => f.fideId as String)
            .toSet();

    final Set<String> favoritedNames =
        favorites
            .map((f) => f.playerName as String)
            .map((name) => name.toLowerCase())
            .toSet();

    // Category priorities (higher number = higher priority)
    const categoryPriority = <String, int>{
      'favorite_player': 4,
      'favorite_event': 3,
      'countryman': 2,
      'high_elo':
          1, // keep minimal; extra penalty applied below to make it rarer
    };

    // Helper to compute a strong freshness boost; live games get an extra layer
    double _recencyBonus(
      DateTime? lastMoveTime, {
      required bool isLive,
      required DateTime now,
    }) {
      if (lastMoveTime == null) return isLive ? 160.0 : 10.0;
      final minutesAgo = now.difference(lastMoveTime).inMinutes;

      if (minutesAgo <= 3) return isLive ? 700.0 : 520.0;
      if (minutesAgo <= 30) return isLive ? 560.0 : 430.0;
      if (minutesAgo <= 120) return isLive ? 380.0 : 300.0;
      if (minutesAgo <= 360) return isLive ? 260.0 : 210.0;
      if (minutesAgo <= 720) return isLive ? 170.0 : 130.0;
      if (minutesAgo <= 1440) return isLive ? 120.0 : 90.0;
      return isLive ? 70.0 : 50.0;
    }

    double _eloBonus(int maxElo) {
      if (maxElo >= 2700) return 20;
      if (maxElo >= 2600) return 12;
      if (maxElo >= 2500) return 6;
      if (maxElo >= 2300) return 2; // Only matters for countrymen
      return 0;
    }

    // Bucket games by category so we can interleave them with weighted round-robin.
    final Map<String, List<_ScoredGame>> buckets = {
      for (final entry in categoryPriority.entries) entry.key: <_ScoredGame>[],
    };
    final List<_ScoredGame> liveGames = [];

    final now = DateTime.now();

    for (final game in _allGames) {
      // Check game categories
      final hasFavorite = _hasFavoritedPlayer(
        game,
        favoritedFideIds,
        favoritedNames,
      );
      final hasEvent = favoriteEventIds.contains(game.tourId);
      final hasCountryman =
          countryCode != null && _hasPlayerFromCountry(game, countryCode);
      final maxElo = _getMaxElo(game);
      final isLive = _isLiveGame(game);

      // Decide category (single highest-priority match)
      String? category;
      if (hasFavorite) {
        category = 'favorite_player';
      } else if (hasEvent) {
        category = 'favorite_event';
      } else if (hasCountryman && maxElo >= 2300) {
        category = 'countryman';
      } else if (maxElo >= 2600) {
        category = 'high_elo';
      }

      if (category == null)
        continue; // Skip games that don't match any category

      // Build a compact score: category weight dominates, live gives an extra bump,
      // recency/ELO provide tie-breakers without causing random spikes.
      final baseWeight = (categoryPriority[category] ?? 0) * 100.0;
      final liveBonus = isLive ? 250.0 : 0.0; // Strong push for live games
      final score =
          baseWeight +
          liveBonus +
          _recencyBonus(
            game.lastMoveTime,
            isLive: isLive,
            now: now,
          ) +
          _eloBonus(maxElo);

      final scored = _ScoredGame(
        game: game,
        score: score,
        category: category,
        isLive: isLive,
        maxElo: maxElo,
      );

      if (isLive) {
        liveGames.add(scored);
      } else {
        buckets[category]!.add(scored);
      }
    }

    // Live games sit at the absolute top, still respecting priority/ELO/recency inside the live slice.
    _sortScoredGames(liveGames, prioritizeElo: true);

    // Sort inside each bucket by score (and ELO/recency where applicable)
    for (final bucket in buckets.values) {
      _sortScoredGames(bucket, prioritizeElo: true);
    }

    // Weighted round-robin: prefer higher categories, but decay per category to keep variety.
    final Map<String, int> pickCounts = {
      for (final entry in categoryPriority.entries) entry.key: 0,
    };

    final List<_ScoredGame> distributed = [];

    while (true) {
      _ScoredGame? bestCandidate;
      String? bestCategory;
      double bestAdjusted = -1;

      for (final entry in buckets.entries) {
        final category = entry.key;
        final games = entry.value;
        if (games.isEmpty) continue;

        final candidate = games.first;
        final picksSoFar = pickCounts[category] ?? 0;

        // Diversity penalty grows as we pick repeatedly from the same category.
        final diversityPenalty = 1 + (picksSoFar * 0.45);
        final highEloPenalty =
            candidate.category == 'high_elo'
                ? 2.5
                : 1.0; // Make high-ELO inserts rarer

        // Extra nudge for live games AFTER diversity penalty to surface them earlier.
        final adjustedScore =
            (candidate.score / (diversityPenalty * highEloPenalty)) +
            (candidate.isLive ? 25.0 : 0.0);

        if (adjustedScore > bestAdjusted) {
          bestAdjusted = adjustedScore;
          bestCandidate = candidate;
          bestCategory = category;
        }
      }

      if (bestCandidate == null || bestCategory == null) break;

      distributed.add(bestCandidate);
      pickCounts[bestCategory] = (pickCounts[bestCategory] ?? 0) + 1;
      buckets[bestCategory]!.removeAt(0);
    }

    // Update games list: live games first, then distributed non-live
    _allGames
      ..clear()
      ..addAll([
        ...liveGames.map((sg) => sg.game),
        ...distributed.map((sg) => sg.game),
      ]);

    // Debug output
    if (distributed.isNotEmpty || liveGames.isNotEmpty) {
      final categoryCounts = <String, int>{};
      int liveCount = 0;
      for (final sg in [...liveGames, ...distributed].take(20)) {
        categoryCounts[sg.category] = (categoryCounts[sg.category] ?? 0) + 1;
        if (sg.isLive) liveCount++;
      }
      debugPrint(
        '[ForYouGames] Top 20 distribution: $categoryCounts, live in top 20: $liveCount',
      );
    }
  }

  /// Sort helper: by score, then recency
  void _sortScoredGames(List<_ScoredGame> games, {bool prioritizeElo = false}) {
    games.sort((a, b) {
      final scoreDiff = b.score.compareTo(a.score);
      if (scoreDiff != 0) return scoreDiff;
      final recencyDiff = _compareByLastMoveTime(a.game, b.game);
      if (recencyDiff != 0) return recencyDiff;
      if (prioritizeElo) {
        final eloDiff = b.maxElo.compareTo(a.maxElo);
        if (eloDiff != 0) return eloDiff;
      }
      return 0;
    });
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
      if (player.fideId > 0 &&
          favoritedFideIds.contains(player.fideId.toString())) {
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
    return game.players!.any(
      (p) => p.fed.toUpperCase() == countryCode.toUpperCase(),
    );
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
  Future<void> refreshIfStale({
    Duration maxAge = const Duration(seconds: 60),
  }) async {
    if (state.isLoading || _isFetchingMore || _isRefreshing) return;

    // Check if preferences are now available but weren't during initial load
    if (!_initialLoadHadPreferences) {
      final favoritesAsync = _ref.read(favoritePlayersProviderNew);
      final favorites = favoritesAsync.valueOrNull ?? [];

      final favoriteEventsAsync = _ref.read(favoriteEventsProvider);
      final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];

      final countryState = _ref.read(countryDropdownProvider);
      final selectedCountry = countryState.value;

      final hasPreferencesNow =
          favorites.isNotEmpty ||
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

  /// Checks if a game hasn't started yet (future pairing)
  bool _isFutureGame(Games game) {
    final status = GameStatus.fromString(game.status);
    final hasMoves = (game.lastMove?.isNotEmpty ?? false) ||
        game.lastMoveTime != null ||
        (game.pgn?.isNotEmpty ?? false);

    // Future game = no moves/logged time, not live, and no result
    return !_isLiveGame(game) && !status.isFinished && !hasMoves;
  }

  @override
  void dispose() {
    _preferenceRefreshDebounce?.cancel();
    super.dispose();
  }
}

// ============================================================================
// MODELS
// ============================================================================

/// Represents games grouped by tournament for UI display
class GroupedTournamentGames {
  GroupedTournamentGames({
    required this.groupKey,
    required this.tourId,
    required this.tourName,
    required this.games,
    required this.hasLiveGames,
  });

  final String groupKey; // Unique per group (pagination-safe)
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
