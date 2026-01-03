import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
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
/// KEY BEHAVIOR:
/// - Games from the same event (group_broadcast_id) are MERGED into one card
/// - Starred (favorite) events appear at the top
/// - Each event card shows top 4 boards from the latest round
/// - Favorite players' games get priority within each event
///
/// REACTIVE: This provider watches favoriteEventsProvider, favoritePlayersProviderNew,
/// and countryDropdownProvider - so it rebuilds immediately when any preference changes.
final groupedForYouGamesProvider = Provider.autoDispose<
  List<GroupedTournamentGames>
>((ref) {
  ref.keepAlive(); // Keep alive to match main provider
  final games = ref.watch(forYouGamesProvider).valueOrNull ?? [];
  final tourToGroupMapping = ref.watch(tourToGroupBroadcastMappingProvider);

  // ============================================================
  // WATCH ALL PREFERENCE PROVIDERS FOR REACTIVE UPDATES
  // When any of these change, this provider rebuilds immediately
  // ============================================================

  // Watch favorite events
  final favoriteEventsAsync = ref.watch(favoriteEventsProvider);
  final favoriteEventIds = favoriteEventsAsync.valueOrNull
      ?.map((e) => e.eventId)
      .toSet() ?? <String>{};

  // Watch favorite players
  final favoritesAsync = ref.watch(favoritePlayersProviderNew);
  final favorites = favoritesAsync.valueOrNull ?? [];
  final favoritedFideIds = favorites
      .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
      .map((f) => f.fideId!)
      .toSet();
  final favoritedNames = favorites
      .map((f) => f.playerName.toLowerCase())
      .toSet();

  // Watch country selection (for reactive refresh when country changes)
  ref.watch(countryDropdownProvider);

  // CRITICAL FIX: Group ALL games by group_broadcast_id (event umbrella)
  // This merges games from same event (e.g., U17, U19 categories) into ONE card
  // No more duplicate cards for the same event!
  final grouped = <String, List<Games>>{};
  final groupOrder = <String>[]; // Track insertion order for stable ordering
  final groupTourNames = <String, String>{}; // Track tour names (use first seen)
  final seenGameIds = <String>{}; // Deduplicate games

  for (final game in games) {
    // Skip duplicate games
    if (seenGameIds.contains(game.id)) continue;
    seenGameIds.add(game.id);

    final tourId = game.tourId;
    final tourName = game.tourSlug;
    // Use group_broadcast_id if available, fallback to tour_id
    final groupKey = tourToGroupMapping[tourId] ?? tourId;

    if (!grouped.containsKey(groupKey)) {
      grouped[groupKey] = [];
      groupOrder.add(groupKey);
      groupTourNames[groupKey] = tourName;
    }

    grouped[groupKey]!.add(game);
  }

  // Hard limit: maximum 4 games per event card in For You tab
  const maxGamesPerEvent = 4;

  // FIRST: Check which groups have favorite players (check ALL games, not just top 4)
  final groupsWithFavoritePlayers = <String>{};
  for (final groupKey in groupOrder) {
    final allGroupGames = grouped[groupKey]!;
    for (final game in allGroupGames) {
      if (_gameHasFavoritePlayer(game, favoritedFideIds, favoritedNames)) {
        groupsWithFavoritePlayers.add(groupKey);
        break;
      }
    }
  }

  // Process each group to select top 4 games from the last round
  // Priority: favorite players first, then by ELO
  final result = <GroupedTournamentGames>[];

  for (final groupKey in groupOrder) {
    final allGroupGames = grouped[groupKey]!;
    final tourName = groupTourNames[groupKey] ?? '';

    // Select top games from last round with favorite player priority
    final selectedGames = _selectTopGamesFromLastRound(
      allGroupGames,
      maxGamesPerEvent,
      favoritedFideIds,
      favoritedNames,
    );

    final hasLiveGames = selectedGames.any((g) => g.status == '*');

    result.add(GroupedTournamentGames(
      groupKey: groupKey,
      tourId: groupKey, // Use group_broadcast_id for navigation
      tourName: tourName,
      games: selectedGames,
      hasLiveGames: hasLiveGames,
    ));
  }

  // Helper to check if an event has favorited player games (uses pre-computed set)
  bool eventHasFavoritePlayer(GroupedTournamentGames group) {
    return groupsWithFavoritePlayers.contains(group.groupKey);
  }

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

  // Get max ELO from event's games for secondary sorting
  int getEventMaxElo(GroupedTournamentGames group) {
    int maxElo = 0;
    for (final game in group.games) {
      final gameMaxElo = _getGameMaxElo(game);
      if (gameMaxElo > maxElo) maxElo = gameMaxElo;
    }
    return maxElo;
  }

  // =============================================================
  // EVENT SORTING - Three-tier categorization (like Current tab)
  // =============================================================
  // Tier 1: Starred events (user explicitly starred)
  // Tier 2: Events with favorite players (hearted)
  // Tier 3: Regular events (sorted by ELO, live as tiebreaker)
  // =============================================================

  // Categorize events into three tiers (matching Current tab approach)
  final starredEvents = <GroupedTournamentGames>[];
  final heartedEvents = <GroupedTournamentGames>[];
  final regularEvents = <GroupedTournamentGames>[];

  for (final event in result) {
    if (favoriteEventIds.contains(event.tourId)) {
      starredEvents.add(event);
    } else if (eventHasFavoritePlayer(event)) {
      heartedEvents.add(event);
    } else {
      regularEvents.add(event);
    }
  }

  // Sort starred events by recency (most recent activity first)
  starredEvents.sort((a, b) {
    final aRecency = getEventRecency(a);
    final bRecency = getEventRecency(b);
    return bRecency.compareTo(aRecency);
  });

  // Sort hearted events by ELO (higher first), then recency
  heartedEvents.sort((a, b) {
    final aMaxElo = getEventMaxElo(a);
    final bMaxElo = getEventMaxElo(b);
    if (aMaxElo != bMaxElo) {
      return bMaxElo.compareTo(aMaxElo);
    }
    final aRecency = getEventRecency(a);
    final bRecency = getEventRecency(b);
    return bRecency.compareTo(aRecency);
  });

  // Sort regular events by ELO only (higher first) - simple approach like Current tab
  regularEvents.sort((a, b) {
    final aMaxElo = getEventMaxElo(a);
    final bMaxElo = getEventMaxElo(b);
    return bMaxElo.compareTo(aMaxElo);
  });

  // Return: starred first, then hearted, then regular (like Current tab)
  return [...starredEvents, ...heartedEvents, ...regularEvents];
});

/// Extracts round number from roundSlug (e.g., "round-5" -> 5)
int _extractRoundNumber(String roundSlug) {
  // Try to extract number from common patterns like "round-5", "round5", "r5"
  final regex = RegExp(r'(\d+)');
  final match = regex.firstMatch(roundSlug);
  if (match != null) {
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }
  return 0;
}

/// Selects top 4 games for an event card
///
/// PRIORITY ORDER:
/// 1. Latest round factor (favorites' latest round first if any)
/// 2. Favorite players (within a round)
/// 3. Higher ELO (within a round)
///
/// CONSISTENCY: Always tries to return exactly [maxGames] (4) games.
List<Games> _selectTopGamesFromLastRound(
  List<Games> allGames,
  int maxGames,
  Set<String> favoritedFideIds,
  Set<String> favoritedNames,
) {
  if (allGames.isEmpty) return [];

  // Sort by ELO only (higher first) - simple approach
  int compareByElo(Games a, Games b) {
    final aMaxElo = _getGameMaxElo(a);
    final bMaxElo = _getGameMaxElo(b);
    return bMaxElo.compareTo(aMaxElo);
  }

  final gamesByRound = <String, List<Games>>{};
  final roundNumbers = <String, int>{};

  for (final game in allGames) {
    final roundId = game.roundId;
    gamesByRound.putIfAbsent(roundId, () => []).add(game);
    if (!roundNumbers.containsKey(roundId)) {
      roundNumbers[roundId] = _extractRoundNumber(game.roundSlug);
    }
  }

  final sortedRoundIds = gamesByRound.keys.toList()
    ..sort((a, b) => (roundNumbers[b] ?? 0).compareTo(roundNumbers[a] ?? 0));

  final hasFavoritesInEvent = allGames.any(
    (game) => _gameHasFavoritePlayer(game, favoritedFideIds, favoritedNames),
  );

  String? latestFavoriteRoundId;
  if (hasFavoritesInEvent) {
    final favoriteRoundIds = sortedRoundIds
        .where(
          (roundId) => gamesByRound[roundId]!.any(
            (game) =>
                _gameHasFavoritePlayer(game, favoritedFideIds, favoritedNames),
          ),
        )
        .toList();
    if (favoriteRoundIds.isNotEmpty) {
      latestFavoriteRoundId = favoriteRoundIds.first;
    }
  }

  final orderedRoundIds = <String>[];
  if (latestFavoriteRoundId != null) {
    orderedRoundIds.add(latestFavoriteRoundId);
  }
  for (final roundId in sortedRoundIds) {
    if (roundId != latestFavoriteRoundId) {
      orderedRoundIds.add(roundId);
    }
  }

  final selectedGames = <Games>[];
  final selectedIds = <String>{};

  void addGames(List<Games> games) {
    for (final game in games) {
      if (selectedGames.length >= maxGames) return;
      if (selectedIds.add(game.id)) {
        selectedGames.add(game);
      }
    }
  }

  for (final roundId in orderedRoundIds) {
    if (selectedGames.length >= maxGames) break;
    final roundGames = gamesByRound[roundId] ?? [];

    if (hasFavoritesInEvent) {
      final favorites = <Games>[];
      final nonFavorites = <Games>[];

      for (final game in roundGames) {
        if (_gameHasFavoritePlayer(game, favoritedFideIds, favoritedNames)) {
          favorites.add(game);
        } else {
          nonFavorites.add(game);
        }
      }

      favorites.sort(compareByElo);
      nonFavorites.sort(compareByElo);

      addGames(favorites);
      addGames(nonFavorites);
    } else {
      final sortedRoundGames = List<Games>.from(roundGames)
        ..sort(compareByElo);
      addGames(sortedRoundGames);
    }
  }

  return selectedGames;
}

/// Checks if a game has a favorited player
bool _gameHasFavoritePlayer(
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
/// Three-tier categorization (matching Current tab approach):
/// Tier 1: Starred events (user explicitly starred) - sorted by recency
/// Tier 2: Events with favorite players (hearted) - sorted by ELO
/// Tier 3: Regular events - sorted by ELO only
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

      // Fetch tour → group_broadcast mapping for proper event grouping
      // This ensures events with categories (U17, U19, etc.) are grouped together
      await _fetchTourToGroupBroadcastMapping();

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
  /// 3. Regular games (sorted by ELO, live as tiebreaker)
  void _sortGamesForFeed(
    List favorites,
    String? countryCode,
    Set<String> favoriteEventIds,
  ) {
    if (_allGames.isEmpty) return;

    debugPrint('[ForYouGames] Sorting ${_allGames.length} games for feed...');

    // Create lookup sets for performance
    final Set<String> favoritedFideIds = favorites
        .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
        .map((f) => f.fideId as String)
        .toSet();

    final Set<String> favoritedNames = favorites
        .map((f) => f.playerName as String)
        .map((name) => name.toLowerCase())
        .toSet();

    // =============================================================
    // THREE-TIER CATEGORIZATION (matching Current tab approach)
    // =============================================================
    // Tier 1: Games from starred events
    // Tier 2: Games with favorite players (hearted)
    // Tier 3: Regular games (sorted by ELO, live as tiebreaker)
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

    // Sort regular games by ELO only (higher first) - simple approach like Current tab
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

