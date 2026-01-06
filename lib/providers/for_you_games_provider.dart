import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============================================================================
// CURRENT TOUR IDS PROVIDER
// ============================================================================

/// Provider for tour IDs that belong to current (non-past) events
/// Used to filter out games from past events in the For You feed
final currentTourIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  ref.keepAlive(); // Cache during session
  final repository = ref.read(groupBroadcastRepositoryProvider);
  return repository.getCurrentTourIds();
});

/// Provider for tour_id → group_broadcast_id mapping
/// Used to group games by their parent event (group_broadcast) instead of individual tours
/// This ensures events with categories (U17, U19, etc.) are grouped together
final tourToGroupBroadcastMappingProvider = StateProvider<Map<String, String>>((ref) {
  ref.keepAlive();
  return {};
});

/// Provider for event favorite players data in For You tab
/// This uses the SAME eventFavoritePlayersCacheProvider as Current tab
/// to ensure consistent hearted event detection
final forYouEventFavoritePlayersProvider = StateProvider<Map<String, EventFavoritePlayers>>((ref) {
  ref.keepAlive();
  return {};
});

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

/// Provider for grouped games (by event/group_broadcast) for UI display
/// Games are grouped by their parent event (group_broadcast_id) to ensure
/// events with categories (U17, U19, etc.) appear under one umbrella event card
///
/// SORTING: Four-tier priority system:
/// - Tier 1: Starred events (sorted by recency)
/// - Tier 2: Hearted events (sorted by favorite player count, then ELO)
/// - Tier 3: Live events (sorted by ELO) - comes AFTER hearted, BEFORE regular
/// - Tier 4: Regular events (sorted by ELO)
///
/// CRITICAL: Uses eventFavoritePlayersCacheProvider for hearted detection
/// This checks ALL players in the event, not just fetched games!
final groupedForYouGamesProvider = Provider.autoDispose<
  List<GroupedTournamentGames>
>((ref) {
  ref.keepAlive();
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];
  final tourToGroupMapping = ref.watch(tourToGroupBroadcastMappingProvider);

  // ============================================================
  // WATCH ALL PREFERENCE PROVIDERS (like Current tab)
  // ============================================================

  // Watch favorite events (starred)
  final favoriteEventsAsync = ref.watch(favoriteEventsProvider);
  final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];
  final starredFavorites = favoriteEvents
      .map((e) => e.eventId)
      .where((id) => id.isNotEmpty)
      .toList();

  // Watch favorite players (for game selection within events)
  final favoritesStateAsync = ref.watch(favoritePlayersNotifierProvider);
  final favoritesState = favoritesStateAsync.valueOrNull;
  final favoritePlayers = favoritesState?.players ?? [];

  // Build integer FIDE ID set (same as Current tab)
  final favoritedFideIds = favoritePlayers
      .where((p) => p.fideId != null && p.fideId! > 0)
      .map((p) => p.fideId!)
      .toSet();
  final favoritedNames = favoritePlayers
      .map((p) => p.name.toLowerCase())
      .toSet();

  // Watch country selection (for reactive refresh)
  ref.watch(countryDropdownProvider);

  // ============================================================
  // CRITICAL: Watch eventFavoritePlayersCacheProvider (SAME AS CURRENT TAB)
  // This is the KEY to consistent hearted detection!
  // ============================================================
  final eventFavoritePlayersCache = ref.watch(eventFavoritePlayersCacheProvider);

  // Also watch For You specific cache (populated by ForYouGamesNotifier)
  final forYouEventFavoritePlayers = ref.watch(forYouEventFavoritePlayersProvider);

  // ============================================================
  // STEP 1: Group games by event (group_broadcast_id)
  // ============================================================
  final grouped = <String, List<Games>>{};
  final groupOrder = <String>[];
  final groupTourNames = <String, String>{};
  final seenGameIds = <String>{};

  for (final game in games) {
    if (seenGameIds.contains(game.id)) continue;
    seenGameIds.add(game.id);

    final tourId = game.tourId;
    final tourName = game.tourSlug;
    final groupKey = tourToGroupMapping[tourId] ?? tourId;

    if (!grouped.containsKey(groupKey)) {
      grouped[groupKey] = [];
      groupOrder.add(groupKey);
      groupTourNames[groupKey] = tourName;
    }
    grouped[groupKey]!.add(game);
  }

  // ============================================================
  // STEP 2: Build eventFavoritePlayerCounts (USING CACHE - LIKE CURRENT TAB)
  // This uses the SAME cache as Current tab, ensuring consistency!
  // ============================================================
  final eventFavoritePlayerCounts = <String, int>{};

  for (final groupKey in groupOrder) {
    // First check the main cache (shared with Current tab)
    final cachedData = eventFavoritePlayersCache[groupKey];
    if (cachedData != null && cachedData.hasFavorites) {
      eventFavoritePlayerCounts[groupKey] = cachedData.count;
      continue;
    }

    // Then check For You specific cache
    final forYouCachedData = forYouEventFavoritePlayers[groupKey];
    if (forYouCachedData != null && forYouCachedData.hasFavorites) {
      eventFavoritePlayerCounts[groupKey] = forYouCachedData.count;
      continue;
    }

    // Fallback: scan fetched games (less reliable but better than nothing)
    final allGroupGames = grouped[groupKey]!;
    final foundFavoriteIds = <int>{};
    final foundFavoriteNames = <String>{};

    for (final game in allGroupGames) {
      if (game.players == null) continue;
      for (final player in game.players!) {
        if (player.fideId > 0 && favoritedFideIds.contains(player.fideId)) {
          foundFavoriteIds.add(player.fideId);
        }
        final lowerName = player.name.toLowerCase();
        if (favoritedNames.contains(lowerName)) {
          foundFavoriteNames.add(lowerName);
        }
      }
    }

    final count = foundFavoriteIds.length + foundFavoriteNames.length;
    if (count > 0) {
      eventFavoritePlayerCounts[groupKey] = count;
    }
  }

  // ============================================================
  // STEP 3: Build list of starred event IDs (handle mapping)
  // ============================================================
  final starredEventSet = starredFavorites.toSet();

  // Build a function to check if groupKey is starred
  bool isGroupStarred(String groupKey, List<Games> groupGames) {
    // Direct match
    if (starredEventSet.contains(groupKey)) return true;
    // Check via mapping (groupKey might be tour_id, but starred uses group_broadcast_id)
    for (final game in groupGames) {
      final mappedId = tourToGroupMapping[game.tourId];
      if (mappedId != null && starredEventSet.contains(mappedId)) return true;
    }
    return false;
  }

  // ============================================================
  // STEP 4: Create GroupedTournamentGames objects
  // ============================================================
  const maxGamesPerEvent = 4;
  final allEvents = <GroupedTournamentGames>[];

  for (final groupKey in groupOrder) {
    final allGroupGames = grouped[groupKey]!;
    final tourName = groupTourNames[groupKey] ?? '';

    final selectedGames = _selectTopGamesFromLastRound(
      allGroupGames,
      maxGamesPerEvent,
      favoritedFideIds,
      favoritedNames,
    );

    final hasLiveGames = selectedGames.any((g) => g.status == '*');

    allEvents.add(GroupedTournamentGames(
      groupKey: groupKey,
      tourId: groupKey,
      tourName: tourName,
      games: selectedGames,
      hasLiveGames: hasLiveGames,
    ));
  }

  // ============================================================
  // STEP 5: FOUR-TIER SORTING
  // Priority: Starred → Hearted → Live → Regular
  // ============================================================

  final starredEvents = <GroupedTournamentGames>[];
  final heartedEvents = <GroupedTournamentGames>[];
  final liveEvents = <GroupedTournamentGames>[];
  final regularEvents = <GroupedTournamentGames>[];

  for (final event in allEvents) {
    final groupGames = grouped[event.groupKey] ?? [];

    if (isGroupStarred(event.groupKey, groupGames)) {
      // Priority 1: Starred by user
      starredEvents.add(event);
    } else if ((eventFavoritePlayerCounts[event.groupKey] ?? 0) > 0) {
      // Priority 2: Has favorite players (hearted)
      heartedEvents.add(event);
    } else if (event.hasLiveGames) {
      // Priority 3: Live events (after hearted)
      liveEvents.add(event);
    } else {
      // Priority 4: Regular events
      regularEvents.add(event);
    }
  }

  // Helper functions for sorting
  int getEventRecency(GroupedTournamentGames group) {
    DateTime? mostRecent;
    for (final game in group.games) {
      final candidate = game.lastMoveTime ?? game.dateStart;
      if (candidate == null) continue;
      if (mostRecent == null || candidate.isAfter(mostRecent)) {
        mostRecent = candidate;
      }
    }
    return mostRecent?.millisecondsSinceEpoch ?? 0;
  }

  int getEventMaxElo(GroupedTournamentGames group) {
    int maxElo = 0;
    for (final game in group.games) {
      final gameMaxElo = _getGameMaxElo(game);
      if (gameMaxElo > maxElo) maxElo = gameMaxElo;
    }
    return maxElo;
  }

  // Sort starred events by recency (most recent first)
  starredEvents.sort((a, b) {
    return getEventRecency(b).compareTo(getEventRecency(a));
  });

  // Sort hearted events by favorite player count (descending), then ELO
  heartedEvents.sort((a, b) {
    final countA = eventFavoritePlayerCounts[a.groupKey] ?? 0;
    final countB = eventFavoritePlayerCounts[b.groupKey] ?? 0;
    if (countA != countB) return countB.compareTo(countA);

    final eloA = getEventMaxElo(a);
    final eloB = getEventMaxElo(b);
    if (eloA != eloB) return eloB.compareTo(eloA);

    return getEventRecency(b).compareTo(getEventRecency(a));
  });

  // Sort live events by ELO (highest first)
  liveEvents.sort((a, b) {
    final eloA = getEventMaxElo(a);
    final eloB = getEventMaxElo(b);
    return eloB.compareTo(eloA);
  });

  // Sort regular events by ELO only
  regularEvents.sort((a, b) {
    final eloA = getEventMaxElo(a);
    final eloB = getEventMaxElo(b);
    return eloB.compareTo(eloA);
  });

  // ============================================================
  // STEP 6: RETURN CONCATENATED LIST
  // Starred → Hearted → Live (by ELO) → Regular (by ELO)
  // ============================================================

  debugPrint('[ForYouGames] === Sorting Result ===');
  debugPrint('[ForYouGames] ${starredEvents.length} starred + ${heartedEvents.length} hearted + ${liveEvents.length} live + ${regularEvents.length} regular');
  debugPrint('[ForYouGames] favoritePlayerCounts: $eventFavoritePlayerCounts');

  // Log first 5 events with their category
  final result = [...starredEvents, ...heartedEvents, ...liveEvents, ...regularEvents];
  for (int i = 0; i < result.length && i < 5; i++) {
    final e = result[i];
    final isS = starredEvents.contains(e);
    final isH = heartedEvents.contains(e);
    final isL = liveEvents.contains(e);
    final tier = isS ? 'STARRED' : (isH ? 'HEARTED' : (isL ? 'LIVE' : 'REGULAR'));
    debugPrint('[ForYouGames] #${i + 1} $tier: ${e.tourName}');
  }

  return result;
});

/// Selects top 4 games for an event card
///
/// PRIORITY ORDER:
/// 1. Favorite players' games first (sorted by ELO)
/// 2. Highest ELO boards (to fill remaining slots)
///
/// CONSISTENCY: Always tries to return exactly [maxGames] (4) games.
/// Selects top games from the last round with favorite player priority
/// Uses INTEGER FIDE IDs for matching (same as Current tab)
List<Games> _selectTopGamesFromLastRound(
  List<Games> allGames,
  int maxGames,
  Set<int> favoritedFideIds,
  Set<String> favoritedNames,
) {
  if (allGames.isEmpty) return [];

  // Separate favorite player games from regular games
  final favoriteGames = <Games>[];
  final regularGames = <Games>[];

  for (final game in allGames) {
    if (_gameHasFavoritePlayer(game, favoritedFideIds, favoritedNames)) {
      favoriteGames.add(game);
    } else {
      regularGames.add(game);
    }
  }

  // Sort both by ELO (highest first)
  int compareByElo(Games a, Games b) {
    return _getGameMaxElo(b).compareTo(_getGameMaxElo(a));
  }
  favoriteGames.sort(compareByElo);
  regularGames.sort(compareByElo);

  // Take favorite games first, then fill with highest ELO regular games
  final selectedGames = <Games>[];
  final selectedIds = <String>{};

  void addGame(Games game) {
    if (selectedGames.length >= maxGames) return;
    if (selectedIds.add(game.id)) {
      selectedGames.add(game);
    }
  }

  for (final game in favoriteGames) {
    addGame(game);
  }
  for (final game in regularGames) {
    addGame(game);
  }

  return selectedGames;
}

/// Checks if a game has a favorited player
/// Uses INTEGER FIDE IDs for matching (same as Current tab)
bool _gameHasFavoritePlayer(
  Games game,
  Set<int> favoritedFideIds,
  Set<String> favoritedNames,
) {
  if (game.players == null) return false;

  for (final player in game.players!) {
    // Match by FIDE ID (integer comparison - same as Current tab)
    if (player.fideId > 0 && favoritedFideIds.contains(player.fideId)) {
      return true;
    }
    // Fallback: match by name (case-insensitive)
    if (favoritedNames.contains(player.name.toLowerCase())) {
      return true;
    }
  }
  return false;
}

/// Gets the maximum ELO from a game's players
int _getGameMaxElo(Games game) {
  if (game.players == null || game.players!.isEmpty) return 0;
  return game.players!.map((p) => p.rating).fold<int>(0, (max, r) => r > max ? r : max);
}

/// Provider for converted games (Games to GamesTourModel)
final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>(
  (ref) {
    ref.keepAlive(); // Keep alive to match main provider
    final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];

    // Filter out games with missing/incomplete player data to prevent crashes
    return games
        .where((game) => game.players != null && game.players!.length >= 2)
        .map((game) => GamesTourModel.fromGame(game))
        .toList();
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
/// Four-tier categorization:
/// Tier 1: Starred events (user explicitly starred) - sorted by recency
/// Tier 2: Events with favorite players (hearted) - sorted by count, then ELO
/// Tier 3: Live events - sorted by ELO (comes AFTER hearted)
/// Tier 4: Regular events - sorted by ELO
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
    // Use SAME provider as Current tab (integer FIDE IDs)
    final futures = <Future<void>>[
      _waitForFuture(() => _ref.read(favoritePlayersNotifierProvider.future)),
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

    // Use SAME provider as Current tab (integer FIDE IDs)
    _ref.listen(
      favoritePlayersNotifierProvider,
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

      // Fetch tour → group_broadcast mapping for proper event grouping
      // This ensures events with categories (U17, U19, etc.) are grouped together
      await _fetchTourToGroupBroadcastMapping();

      // CRITICAL: Fetch favorite player data for all events
      // This ensures hearted detection works like Current tab
      await _fetchEventFavoritePlayersData();

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

      // Update mapping for any new tour IDs
      await _fetchTourToGroupBroadcastMapping();

      // Fetch favorite player data for new events
      await _fetchEventFavoritePlayersData();

      state = AsyncValue.data(List<Games>.from(_allGames));
    } catch (e) {
      debugPrint('[ForYouGames] Error loading more: $e');
    } finally {
      _isFetchingMore = false;
    }
  }

  /// Fetch games from ALL current events
  ///
  /// NEW APPROACH: Fetch all games from current events, then prioritize based on:
  /// 1. Starred (favorite) events - highest priority
  /// 2. Games with favorited players
  /// 3. Games from user's country (countrymen)
  /// 4. Higher ELO games
  ///
  /// This ensures a RICH feed with many events, not just restricted to favorites.
  Future<void> _fetchGames({required bool isInitialLoad}) async {
    final repository = _ref.read(gameRepositoryProvider);

    // Get current (non-past) tour IDs - these are ALL events from Current tab
    Set<String> currentTourIds = {};
    try {
      currentTourIds = await _ref.read(currentTourIdsProvider.future);
      debugPrint('[ForYouGames] Loaded ${currentTourIds.length} current tour IDs');
    } catch (e) {
      debugPrint('[ForYouGames] Error loading current tour IDs: $e');
    }

    if (currentTourIds.isEmpty) {
      debugPrint('[ForYouGames] No current events found!');
      _hasMore = false;
      return;
    }

    // Get user preferences for prioritization
    // Use SAME provider as Current tab (integer FIDE IDs)
    final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
    final favoritesState = favoritesAsync.valueOrNull;
    final favorites = favoritesState?.players ?? [];

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

    // Check if we have any preferences at all
    final hasAnyPreferences = favorites.isNotEmpty ||
        favoriteEvents.isNotEmpty ||
        (selectedCountry != null && selectedCountry.countryCode.isNotEmpty);

    debugPrint('[ForYouGames] === Fetching ALL current events games ===');
    debugPrint('[ForYouGames] Current events: ${currentTourIds.length}');
    debugPrint('[ForYouGames] Has preferences: $hasAnyPreferences');
    if (hasAnyPreferences) {
      debugPrint('[ForYouGames]   - Favorites: ${favorites.length}');
      debugPrint('[ForYouGames]   - Favorite events: ${favoriteEvents.length}');
      debugPrint('[ForYouGames]   - Country: ${selectedCountry?.countryCode}');
    } else {
      debugPrint('[ForYouGames]   → No preferences set, using ELO/live/recency scoring');
    }

    final newGames = <Games>[];
    final seenGameIds = _allGames.map((g) => g.id).toSet();

    // Helper to deduplicate and filter future games
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

    // === FETCH ALL GAMES FROM CURRENT EVENTS ===
    // This is the key change: fetch from ALL current tours, not just filtered ones
    try {
      final currentGamesLimit = _pageSize * 10; // Fetch more to cover all events
      final offset = isInitialLoad ? 0 : _allGames.length;

      final allCurrentGames = await repository.getGamesFromTourIds(
        tourIds: currentTourIds.toList(),
        limit: currentGamesLimit,
        offset: offset,
      );

      addUniqueGames(allCurrentGames);
      debugPrint(
        '[ForYouGames] Fetched ${allCurrentGames.length} games from ${currentTourIds.length} current events',
      );
    } catch (e) {
      debugPrint('[ForYouGames] Error fetching current events games: $e');
    }

    if (newGames.isNotEmpty) {
      _allGames.addAll(newGames);
      _emptyFetchCount = 0;

      // Sort games with priority-based scoring
      if (isInitialLoad) {
        final favoriteEventIds = favoriteEvents
            .map((e) => e.eventId)
            .where((id) => id.isNotEmpty)
            .toSet();

        _sortGamesForFeed(
          favorites,
          selectedCountry?.countryCode,
          favoriteEventIds,
        );

        _initialGameIds.addAll(_allGames.map((g) => g.id));
      }
    } else {
      _emptyFetchCount++;
      debugPrint('[ForYouGames] Empty fetch #$_emptyFetchCount');
    }

    _hasMore = newGames.length >= _pageSize;
    debugPrint(
      '[ForYouGames] Total games: ${_allGames.length}, Has more: $_hasMore',
    );

    _lastFetchAt = DateTime.now();
  }

  /// Sort games for the For You feed with three-tier categorization (like Current tab)
  ///
  /// Tier order:
  /// 1. Games from starred (favorite) events
  /// 2. Games with favorited players (hearted)
  /// 3. Regular games (sorted by ELO only - NO live priority)
  void _sortGamesForFeed(
    List<PlayerStandingModel> favorites,
    String? countryCode,
    Set<String> favoriteEventIds,
  ) {
    if (_allGames.isEmpty) return;

    debugPrint('[ForYouGames] Sorting ${_allGames.length} games for feed...');

    // Create lookup sets for performance
    // Use INTEGER FIDE IDs (same as Current tab)
    final favoritedFideIds = favorites
        .where((f) => f.fideId != null && f.fideId! > 0)
        .map((f) => f.fideId!)
        .toSet();

    // Use .name for PlayerStandingModel (from favoritePlayersNotifierProvider)
    final favoritedNames = favorites
        .map((f) => f.name.toLowerCase())
        .toSet();

    // =============================================================
    // THREE-TIER CATEGORIZATION (matching Current tab approach)
    // =============================================================
    // Tier 1: Games from starred events
    // Tier 2: Games with favorite players (hearted)
    // Tier 3: Regular games (sorted by ELO only - NO live priority)
    // =============================================================

    final starredGames = <Games>[];
    final heartedGames = <Games>[];
    final regularGames = <Games>[];

    // Get current tour → group_broadcast mapping to check favorites correctly
    final tourToGroupMapping = _ref.read(tourToGroupBroadcastMappingProvider);

    for (final game in _allGames) {
      // Use mapped group_broadcast_id if available, otherwise fallback to tourId
      final effectiveEventId = tourToGroupMapping[game.tourId] ?? game.tourId;
      final isFromFavoriteEvent = favoriteEventIds.contains(effectiveEventId);
      final hasFavoritePlayer = _hasFavoritedPlayer(
        game,
        favoritedFideIds,
        favoritedNames,
      );

      if (isFromFavoriteEvent) {
        starredGames.add(game);
      } else if (hasFavoritePlayer) {
        heartedGames.add(game);
      } else {
        regularGames.add(game);
      }
    }

    // Helper to get recency score
    int getRecency(Games game) {
      return game.lastMoveTime?.millisecondsSinceEpoch ??
             game.dateStart?.millisecondsSinceEpoch ?? 0;
    }

    // Sort starred games by recency (most recent first)
    starredGames.sort((a, b) {
      return getRecency(b).compareTo(getRecency(a));
    });

    // Sort hearted games by ELO (higher first), then recency
    heartedGames.sort((a, b) {
      final aMaxElo = _getMaxElo(a);
      final bMaxElo = _getMaxElo(b);
      if (aMaxElo != bMaxElo) {
        return bMaxElo.compareTo(aMaxElo);
      }
      return getRecency(b).compareTo(getRecency(a));
    });

    // Sort regular games by ELO only (higher first) - NO LIVE PRIORITY
    regularGames.sort((a, b) {
      final aMaxElo = _getMaxElo(a);
      final bMaxElo = _getMaxElo(b);
      return bMaxElo.compareTo(aMaxElo);
    });

    // Combine: starred first, then hearted, then regular
    _allGames
      ..clear()
      ..addAll(starredGames)
      ..addAll(heartedGames)
      ..addAll(regularGames);

    // Debug output
    debugPrint(
      '[ForYouGames] Sorted: ${starredGames.length} starred, '
      '${heartedGames.length} hearted, ${regularGames.length} regular',
    );
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

  bool _isLiveGame(Games game) {
    return game.status == '*' || game.status == 'ongoing';
  }

  /// Checks if a game has a favorited player
  /// Uses INTEGER FIDE IDs for matching (same as Current tab)
  bool _hasFavoritedPlayer(
    Games game,
    Set<int> favoritedFideIds,
    Set<String> favoritedNames,
  ) {
    if (game.players == null) return false;

    for (final player in game.players!) {
      // Match by FIDE ID (integer comparison - same as Current tab)
      if (player.fideId > 0 && favoritedFideIds.contains(player.fideId)) {
        return true;
      }
      // Fallback: match by name (case-insensitive)
      if (favoritedNames.contains(player.name.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  int _getMaxElo(Games game) {
    if (game.players == null || game.players!.isEmpty) return 0;
    return game.players!.map((p) => p.rating).reduce((a, b) => a > b ? a : b);
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
      // Use SAME provider as Current tab (integer FIDE IDs)
      final favoritesAsync = _ref.read(favoritePlayersNotifierProvider);
      final favoritesState = favoritesAsync.valueOrNull;
      final favorites = favoritesState?.players ?? [];

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

  /// Fetch tour_id → group_broadcast_id mapping for proper event grouping
  /// This ensures events with categories (U17, U19, etc.) appear under one event card
  Future<void> _fetchTourToGroupBroadcastMapping() async {
    if (_allGames.isEmpty) return;

    try {
      // Collect unique tour IDs from all games
      final tourIds = _allGames.map((g) => g.tourId).toSet().toList();

      debugPrint('[ForYouGames] Fetching tour → group_broadcast mapping for ${tourIds.length} tours');

      final repository = _ref.read(groupBroadcastRepositoryProvider);
      final mapping = await repository.getTourToGroupBroadcastMapping(tourIds);

      debugPrint('[ForYouGames] Got mapping for ${mapping.length} tours');

      // Update the mapping provider
      _ref.read(tourToGroupBroadcastMappingProvider.notifier).state = mapping;
    } catch (e) {
      debugPrint('[ForYouGames] Error fetching tour → group_broadcast mapping: $e');
      // Continue without mapping - games will be grouped by tour_id as fallback
    }
  }

  /// CRITICAL: Fetch favorite player data for all events in the For You feed
  /// This uses the SAME approach as Current tab's eventFavoritePlayersProvider
  /// to ensure consistent hearted event detection
  Future<void> _fetchEventFavoritePlayersData() async {
    if (_allGames.isEmpty) return;

    try {
      // Get favorite players
      final favoritesState = await _ref.read(favoritePlayersNotifierProvider.future);
      final favoritePlayers = favoritesState.players;

      if (favoritePlayers.isEmpty) {
        debugPrint('[ForYouGames] No favorite players, skipping event favorite player fetch');
        return;
      }

      // Get favorite FIDE IDs
      final favoriteFideIds = favoritePlayers
          .where((p) => p.fideId != null && p.fideId! > 0)
          .map((p) => p.fideId!)
          .toSet();

      if (favoriteFideIds.isEmpty) {
        debugPrint('[ForYouGames] No favorite FIDE IDs, skipping event favorite player fetch');
        return;
      }

      // Get unique event IDs (group_broadcast_ids)
      final tourToGroupMapping = _ref.read(tourToGroupBroadcastMappingProvider);
      final eventIds = <String>{};
      for (final game in _allGames) {
        final eventId = tourToGroupMapping[game.tourId] ?? game.tourId;
        eventIds.add(eventId);
      }

      debugPrint('[ForYouGames] Checking ${eventIds.length} events for favorite players');

      // For each event, check if it has favorite players using eventFavoritePlayersProvider
      final forYouCache = <String, EventFavoritePlayers>{};

      for (final eventId in eventIds) {
        try {
          // Use the same provider that Current tab uses
          final eventFavoritePlayers = await _ref.read(
            eventFavoritePlayersProvider(eventId).future,
          );

          if (eventFavoritePlayers.hasFavorites) {
            forYouCache[eventId] = eventFavoritePlayers;
            debugPrint('[ForYouGames] Event $eventId has ${eventFavoritePlayers.count} favorite players');
          }
        } catch (e) {
          // Silently continue - event might not have tour data
        }
      }

      // Update the For You specific cache
      _ref.read(forYouEventFavoritePlayersProvider.notifier).state = forYouCache;

      debugPrint('[ForYouGames] Found ${forYouCache.length} events with favorite players');
    } catch (e) {
      debugPrint('[ForYouGames] Error fetching event favorite players: $e');
    }
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
