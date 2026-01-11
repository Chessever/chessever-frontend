import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============================================================================
// CONSTANTS
// ============================================================================

/// Number of games to show per event card - HARDCODED
const int kGamesPerEvent = 4;

// ============================================================================
// FOR YOU EVENTS PROVIDER - WITH PRE-FETCHED HEART DATA
// ============================================================================

/// Provider for For You events - REACTIVE and WAITS for heart data before showing
///
/// CRITICAL: Unlike Current tab which sorts lazily, For You MUST:
/// 1. Load events
/// 2. Pre-fetch eventFavoritePlayersProvider for ALL events
/// 3. Populate the cache
/// 4. THEN sort with correct data
/// 5. THEN emit sorted events
///
/// REACTIVE: Automatically re-sorts when:
/// - User stars/unstars an event (favoriteEventsProvider)
/// - User favorites/unfavorites a player (favoritePlayersNotifierProvider)
/// - Live status changes (liveGroupBroadcastIdsProvider)
///
/// User sees shimmer until step 5 completes.
final forYouEventsProvider = FutureProvider.autoDispose<List<GroupEventCardModel>>((ref) async {
  ref.keepAlive();

  debugPrint('[ForYou] === Starting forYouEventsProvider ===');

  // =========================================================================
  // WATCH REACTIVE DEPENDENCIES - triggers rebuild when these change
  // =========================================================================

  // Watch favorite events (starred) - rebuilds when user stars/unstars
  final favoriteEventsAsync = ref.watch(favoriteEventsProvider);
  final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];

  // Watch favorite players - rebuilds when user adds/removes favorite players
  // Use watch on the provider (not .future) to establish reactivity without causing infinite loops
  final favoritePlayersAsync = ref.watch(favoritePlayersNotifierProvider);
  // Then read the value - this doesn't cause rebuilds during the await
  await favoritePlayersAsync.maybeWhen(
    data: (_) => Future.value(),
    orElse: () => ref.read(favoritePlayersNotifierProvider.future),
  );

  // Read live IDs (not watch) - StreamProvider emits too frequently and causes infinite rebuilds
  // Live status is refreshed when user pulls to refresh
  final liveIdsAsync = ref.read(liveGroupBroadcastIdsProvider);
  final liveIds = liveIdsAsync.valueOrNull ?? [];

  // =========================================================================
  // LOAD EVENTS
  // =========================================================================

  // Step 1: Get current broadcasts (same source as Current tab)
  final broadcasts = await ref
      .read(groupBroadcastLocalStorage(GroupEventCategory.current))
      .fetchGroupBroadcasts();

  if (broadcasts.isEmpty) {
    debugPrint('[ForYou] No broadcasts found');
    return [];
  }

  debugPrint('[ForYou] Loaded ${broadcasts.length} broadcasts');

  // Step 2: Convert to card models with live status
  final models = broadcasts
      .map((b) => GroupEventCardModel.fromGroupBroadcast(b, liveIds))
      .toList();

  // =========================================================================
  // PRE-FETCH HEART DATA FOR ALL EVENTS
  // =========================================================================

  // Step 3: PRE-FETCH favorite player data for ALL events in parallel
  // This is the KEY difference from Current tab
  debugPrint('[ForYou] Pre-fetching favorite player data for ${models.length} events...');

  // Fetch all in parallel - collect results WITHOUT updating cache yet
  // This avoids triggering 54 state updates that cause widget rebuilds
  final futures = models.map((event) async {
    try {
      final data = await ref.read(eventFavoritePlayersProvider(event.id).future);
      return MapEntry(event.id, data);
    } catch (e) {
      debugPrint('[ForYou] Error fetching favorite players for ${event.id}: $e');
      return MapEntry(event.id, const EventFavoritePlayers.empty());
    }
  }).toList();

  // Wait for ALL to complete
  final results = await Future.wait(futures);

  debugPrint('[ForYou] Finished pre-fetching favorite player data');

  // Step 4: Build the map from results (don't use cache to avoid state updates)
  final eventFavoritePlayersMap = Map.fromEntries(results);

  // Update cache ONCE at the end with all data (single state update)
  ref.read(eventFavoritePlayersCacheProvider.notifier).updateCacheBatch(eventFavoritePlayersMap);

  debugPrint('[ForYou] Cache has ${eventFavoritePlayersMap.length} entries');

  // Count how many have favorites
  final heartedCount = eventFavoritePlayersMap.values.where((v) => v.hasFavorites).length;
  debugPrint('[ForYou] Found $heartedCount events with favorite players');

  // =========================================================================
  // SORT WITH COMPLETE DATA
  // =========================================================================

  // Step 5: Get starred event IDs and timestamps
  final starredIds = favoriteEvents.map((e) => e.eventId).toList();

  // Build timestamp map for sorting
  final favoriteTimestamps = <String, DateTime>{};
  for (final fav in favoriteEvents) {
    favoriteTimestamps[fav.eventId] = fav.createdAt;
  }

  debugPrint('[ForYou] Found ${starredIds.length} starred events');

  // Step 6: Sort with COMPLETE data
  final sortedModels = ref.read(tournamentSortingServiceProvider).sortBasedOnFavorite(
    tours: models,
    favorites: starredIds,
    eventFavoritePlayersMap: eventFavoritePlayersMap,
    favoriteTimestamps: favoriteTimestamps,
  );

  debugPrint('[ForYou] Sorted ${sortedModels.length} events');

  // Log the first few events for debugging
  for (int i = 0; i < sortedModels.length && i < 5; i++) {
    final event = sortedModels[i];
    final isStarred = starredIds.contains(event.id);
    final heartData = eventFavoritePlayersMap[event.id];
    final isHearted = heartData?.hasFavorites ?? false;
    debugPrint('[ForYou] Event $i: ${event.title.substring(0, event.title.length.clamp(0, 30))} | starred=$isStarred | hearted=$isHearted (${heartData?.count ?? 0})');
  }

  return sortedModels;
});

// ============================================================================
// LAZY GAMES PER EVENT PROVIDER
// ============================================================================

/// Provider for games of a specific event - loads LAZILY with shimmer
/// Fetches exactly 4 games (top boards with favorite player priority)
final eventGamesProvider = FutureProvider.autoDispose
    .family<List<Games>, String>((ref, eventId) async {
  ref.keepAlive();

  debugPrint('[ForYou] Loading $kGamesPerEvent games for event: $eventId');

  final repository = ref.read(gameRepositoryProvider);
  final groupBroadcastRepo = ref.read(groupBroadcastRepositoryProvider);

  // Get favorite players for priority
  final favoritesState = ref.read(favoritePlayersNotifierProvider).valueOrNull;
  final favoritePlayers = favoritesState?.players ?? [];
  final favoriteFideIds = favoritePlayers
      .where((p) => p.fideId != null && p.fideId! > 0)
      .map((p) => p.fideId!)
      .toSet();

  // Get tour IDs for this event (event may have multiple tours/categories)
  List<String> tourIds;
  try {
    tourIds = await groupBroadcastRepo.getTourIdsForGroupBroadcast(eventId);
    if (tourIds.isEmpty) {
      tourIds = [eventId]; // Fallback to event ID itself
    }
  } catch (e) {
    tourIds = [eventId];
  }

  // Fetch games from these tours
  final allGames = await repository.getGamesFromTourIds(
    tourIds: tourIds,
    limit: 50, // Fetch more to filter
    offset: 0,
  );

  if (allGames.isEmpty) return [];

  // Filter out future games (no moves yet)
  final playedGames = allGames.where((g) => _hasStarted(g)).toList();

  if (playedGames.isEmpty) return [];

  // Find latest round
  final latestRoundGames = _getLatestRoundGames(playedGames);

  // Select 4 games with favorite player priority
  final selectedGames = _selectGamesWithFavoritePriority(
    latestRoundGames,
    favoriteFideIds,
    kGamesPerEvent,
  );

  debugPrint('[ForYou] Selected ${selectedGames.length} games for event $eventId');

  return selectedGames;
});

/// Check if game has started (not a future pairing)
bool _hasStarted(Games game) {
  final isLive = game.status == '*' || game.status == 'ongoing';
  final hasMoves = (game.lastMove?.isNotEmpty ?? false) ||
      game.lastMoveTime != null ||
      (game.pgn?.isNotEmpty ?? false);
  final isFinished = game.status == '1-0' ||
      game.status == '0-1' ||
      game.status == '1/2-1/2' ||
      game.status == '½-½';

  return isLive || hasMoves || isFinished;
}

/// Get the most relevant games for display
/// Priority: Live games first (across ALL categories), then ALL finished games
/// sorted by ELO.
///
/// IMPORTANT: When no live games exist, we return ALL played games and let
/// _selectGamesWithFavoritePriority sort by ELO. This ensures higher-rated
/// categories (e.g., "Blitz Men" with 2700+ ELO) are shown over lower-rated
/// categories (e.g., "Blitz Women" with 2400 ELO) even if the lower-rated
/// category finished more recently.
List<Games> _getLatestRoundGames(List<Games> games) {
  if (games.isEmpty) return [];

  // First priority: Get all LIVE games across all categories/rounds
  final liveGames = games.where((g) => g.status == '*').toList();

  if (liveGames.isNotEmpty) {
    // Return all live games - sorting by ELO happens in _selectGamesWithFavoritePriority
    return liveGames;
  }

  // No live games - return ALL played games
  // The ELO-based sorting in _selectGamesWithFavoritePriority will ensure
  // that the highest-rated games are selected, regardless of which category
  // or round they came from.
  //
  // This fixes the "Tata Steel" issue where Blitz Women games were shown
  // instead of higher-rated Blitz Men games just because Women played later.
  return games;
}

/// Select games with favorite player priority, then by highest ELO
/// Matches the sorting philosophy of the Games tab where top boards appear first
List<Games> _selectGamesWithFavoritePriority(
  List<Games> games,
  Set<int> favoriteFideIds,
  int count,
) {
  if (games.isEmpty) return [];

  // Separate games with favorite players
  final favoriteGames = <Games>[];
  final regularGames = <Games>[];

  for (final game in games) {
    if (_hasFavoritePlayer(game, favoriteFideIds)) {
      favoriteGames.add(game);
    } else {
      regularGames.add(game);
    }
  }

  // Sort favorite games by highest ELO (descending)
  favoriteGames.sort((a, b) => _getMaxElo(b).compareTo(_getMaxElo(a)));

  // Sort regular games by highest ELO (descending) - top rated games first
  // This matches the Games tab where board 1 (highest ELO) appears first
  regularGames.sort((a, b) => _getMaxElo(b).compareTo(_getMaxElo(a)));

  // Take favorite games first, then fill with highest ELO regular games
  final result = <Games>[];
  result.addAll(favoriteGames.take(count));

  if (result.length < count) {
    final existingIds = result.map((g) => g.id).toSet();
    for (final game in regularGames) {
      if (!existingIds.contains(game.id)) {
        result.add(game);
        if (result.length >= count) break;
      }
    }
  }

  return result.take(count).toList();
}

bool _hasFavoritePlayer(Games game, Set<int> favoriteFideIds) {
  if (game.players == null || favoriteFideIds.isEmpty) return false;
  return game.players!.any((p) => favoriteFideIds.contains(p.fideId));
}

int _getMaxElo(Games game) {
  if (game.players == null || game.players!.isEmpty) return 0;
  return game.players!.map((p) => p.rating).fold<int>(0, (max, r) => r > max ? r : max);
}

// ============================================================================
// BACKWARD COMPATIBILITY
// ============================================================================

/// Stub provider for backward compatibility with chessboard navigation
/// Returns empty list since games are now loaded lazily per event
/// The chessboard screen falls back to widget.games when this is empty
final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>((ref) {
  // Games are now loaded lazily per event, so this returns empty
  // The chessboard screen uses widget.games as fallback
  return const [];
});

// ============================================================================
// ANIMATION TRACKING
// ============================================================================

/// Global set to track which game IDs have been animated
final forYouAnimatedGameIds = <String>{};

/// Global set to track which event IDs have been animated
final forYouAnimatedEventIds = <String>{};
