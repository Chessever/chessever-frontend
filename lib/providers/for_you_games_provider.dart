import 'dart:async';

import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int kGamesPerEvent = 4;
const int _kPageSize = 20;
const Duration _kForYouStaleThreshold = Duration(minutes: 5);

// ============================================================================
// FOR YOU EVENTS - PAGINATED WITH SUPABASE QUERIES
// ============================================================================

class ForYouState {
  final List<GroupEventCardModel> events;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  const ForYouState({
    this.events = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  ForYouState copyWith({
    List<GroupEventCardModel>? events,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return ForYouState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class ForYouNotifier extends StateNotifier<ForYouState> {
  final Ref ref;
  int _offset = 0;
  bool _isFetching = false;
  DateTime? _lastRefreshAt;

  ForYouNotifier(this.ref) : super(const ForYouState(isLoading: true)) {
    _setupListeners();
    _loadInitial();
  }

  void _setupListeners() {
    // Listen to favorite events changes and re-sort list immediately
    ref.listen(favoriteEventsProvider, (_, __) => _reSortList());

    // Listen to favorite player cache updates (affects heart counts)
    ref.listen(eventFavoritePlayersCacheProvider, (_, __) => _reSortList());
  }

  Future<void> _reSortList() async {
    if (state.events.isEmpty) return;

    // Re-sort current events list with updated favorite data
    final sorted = await _sortModels(state.events);
    if (mounted) {
      state = state.copyWith(events: sorted);
    }
  }

  Future<void> _loadInitial() async {
    await _fetchPage(isInitial: true);
  }

  Future<void> refresh() async {
    _offset = 0;
    state = const ForYouState(isLoading: true);
    ref.invalidate(eventGamesProvider);
    await _fetchPage(isInitial: true);
  }

  Future<void> refreshIfStale({
    Duration maxAge = _kForYouStaleThreshold,
  }) async {
    if (_isFetching || state.isLoading) return;
    final lastRefreshAt = _lastRefreshAt;
    if (lastRefreshAt == null ||
        DateTime.now().difference(lastRefreshAt) >= maxAge) {
      await refresh();
    }
  }

  Future<void> loadMore() async {
    if (_isFetching || !state.hasMore || state.isLoading) return;
    await _fetchPage(isInitial: false);
  }

  /// Removes an event from the rendered For You list.
  /// Used by the UI when an event resolves to zero available games.
  void removeEvent(String eventId) {
    if (!mounted) return;
    if (!state.events.any((event) => event.id == eventId)) return;

    state = state.copyWith(
      events: state.events.where((event) => event.id != eventId).toList(),
    );
  }

  Future<void> _fetchPage({required bool isInitial}) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      // Read filter state
      final appliedFilters = ref.read(forYouAppliedFilterProvider);

      // Parse filters
      final formatFilters =
          appliedFilters.formatsAndStates
              .where(
                (f) => ['blitz', 'rapid', 'standard'].contains(f.toLowerCase()),
              )
              .map((f) => f.toLowerCase())
              .toList();

      final statusFilters =
          appliedFilters.formatsAndStates
              .where((f) => ['live', 'completed'].contains(f.toLowerCase()))
              .map((f) => f.toLowerCase())
              .toSet();

      final minElo = appliedFilters.eloRange.start.round();
      final maxElo = appliedFilters.eloRange.end.round();
      final hasEloFilter =
          minElo > defaultFilterPopupState.eloRange.start.round() ||
          maxElo < defaultFilterPopupState.eloRange.end.round();

      // Query Supabase with filters
      final repo = ref.read(groupBroadcastRepositoryProvider);
      final broadcasts = await repo.getCurrentGroupBroadcasts(
        limit: _kPageSize,
        offset: _offset,
        timeControlFilters: formatFilters.isNotEmpty ? formatFilters : null,
        minElo: hasEloFilter ? minElo : null,
        maxElo: hasEloFilter ? maxElo : null,
      );

      debugPrint(
        '[ForYou] Fetched ${broadcasts.length} from Supabase (offset: $_offset, filters: format=$formatFilters, elo=$hasEloFilter)',
      );

      // Get live IDs for status filtering
      final liveIds = ref.read(liveGroupBroadcastIdsProvider).valueOrNull ?? [];

      // Apply status filter (live/completed) - can't do in DB query
      List<GroupBroadcast> filteredBroadcasts = broadcasts;
      if (statusFilters.isNotEmpty) {
        filteredBroadcasts =
            broadcasts.where((tour) {
              final isLive = liveIds.contains(tour.id);
              return (statusFilters.contains('live') && isLive) ||
                  (statusFilters.contains('completed') && !isLive);
            }).toList();
      }

      // Convert to models
      final models =
          filteredBroadcasts
              .map((b) => GroupEventCardModel.fromGroupBroadcast(b, liveIds))
              .toList();

      // Pre-fetch heart data in background — don't block page render.
      // This prevents For You from saturating the HTTP connection pool
      // and starving other tabs (e.g. Current) of network access.
      // 5s timeout prevents indefinite stalling if any provider hangs.
      _prefetchHeartData(models)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('[ForYou] _prefetchHeartData timed out after 5s');
            },
          )
          .then((_) {
            if (mounted) _reSortList();
          });

      // Sort this batch (without heart data initially — will re-sort once heart data arrives)
      final sortedModels = await _sortModels(models);

      // Update state
      if (isInitial) {
        state = ForYouState(
          events: sortedModels,
          isLoading: false,
          hasMore: broadcasts.length >= _kPageSize,
        );
        _lastRefreshAt = DateTime.now();
      } else {
        state = state.copyWith(
          events: [...state.events, ...sortedModels],
          hasMore: broadcasts.length >= _kPageSize,
        );
      }

      _offset += broadcasts.length;
    } catch (e, stack) {
      debugPrint('[ForYou] Error: $e');
      debugPrint('[ForYou] Stack: $stack');
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      _isFetching = false;
    }
  }

  /// Prefetch heart (favorite-player) data for a batch of events.
  ///
  /// Uses a single batch query to fetch tours for ALL events at once,
  /// then computes heart data locally. This replaces the previous N+1
  /// pattern (20 individual Supabase queries) with 1 batch query.
  Future<void> _prefetchHeartData(List<GroupEventCardModel> models) async {
    try {
      // 1. Get the user's favorite players from the new provider (in-memory, no Supabase call).
      // Data is already synced by the auth flow — reading synchronously avoids
      // a redundant Supabase round-trip that the old autoDispose provider triggered.
      final favoritePlayers =
          ref.read(favoritePlayersProviderNew).valueOrNull ?? [];

      if (favoritePlayers.isEmpty) {
        // No favorites — cache empty results and return early
        final map = {
          for (final m in models) m.id: const EventFavoritePlayers.empty(),
        };
        ref
            .read(eventFavoritePlayersCacheProvider.notifier)
            .updateCacheBatch(map);
        return;
      }

      final favoriteFideIds =
          favoritePlayers
              .where((p) => p.fideId != null)
              .map((p) => int.tryParse(p.fideId!))
              .whereType<int>()
              .toSet();

      if (favoriteFideIds.isEmpty) {
        final map = {
          for (final m in models) m.id: const EventFavoritePlayers.empty(),
        };
        ref
            .read(eventFavoritePlayersCacheProvider.notifier)
            .updateCacheBatch(map);
        return;
      }

      // 2. Batch-fetch tours for ALL events in ONE query
      final eventIds = models.map((m) => m.id).toList();
      final tourRepo = ref.read(tourRepositoryProvider);
      final toursMap = await tourRepo.getToursByGroupBroadcastIds(eventIds);

      // 3. Compute heart data locally for each event
      final resultMap = <String, EventFavoritePlayers>{};

      for (final model in models) {
        final tours = toursMap[model.id] ?? [];
        final eventPlayerFideIds = <int>{};

        for (final tour in tours) {
          for (final player in tour.players) {
            if (player.fideId != null && player.fideId! > 0) {
              eventPlayerFideIds.add(player.fideId!);
            }
          }
        }

        final matchingFideIds =
            eventPlayerFideIds.intersection(favoriteFideIds).toList();

        resultMap[model.id] =
            matchingFideIds.isEmpty
                ? const EventFavoritePlayers.empty()
                : EventFavoritePlayers(
                  count: matchingFideIds.length,
                  fideIds: matchingFideIds,
                );
      }

      ref
          .read(eventFavoritePlayersCacheProvider.notifier)
          .updateCacheBatch(resultMap);
    } catch (e) {
      debugPrint('[ForYou] Error in batch _prefetchHeartData: $e');
      // On error, cache empty for all events so we don't retry endlessly
      final map = {
        for (final m in models) m.id: const EventFavoritePlayers.empty(),
      };
      ref
          .read(eventFavoritePlayersCacheProvider.notifier)
          .updateCacheBatch(map);
    }
  }

  Future<List<GroupEventCardModel>> _sortModels(
    List<GroupEventCardModel> models,
  ) async {
    final favoriteEventsAsync = ref.read(favoriteEventsProvider);
    final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];
    final starredIds = favoriteEvents.map((e) => e.eventId).toList();

    final favoriteTimestamps = <String, DateTime>{};
    for (final fav in favoriteEvents) {
      favoriteTimestamps[fav.eventId] = fav.createdAt;
    }

    final cache = ref.read(eventFavoritePlayersCacheProvider);

    return ref
        .read(tournamentSortingServiceProvider)
        .sortBasedOnFavorite(
          tours: models,
          favorites: starredIds,
          eventFavoritePlayersMap: cache,
          favoriteTimestamps: favoriteTimestamps,
        );
  }
}

final forYouEventsProvider =
    StateNotifierProvider.autoDispose<ForYouNotifier, ForYouState>((ref) {
      ref.keepAlive();
      return ForYouNotifier(ref);
    });

// ============================================================================
// LAZY GAMES PER EVENT PROVIDER
// Uses the same sorting logic as the Games tab in event detail screen:
// 1. Pinned games first (manual + auto, preserving pin order)
// 2. Round number DESCENDING (latest round first)
// 3. Game number DESCENDING
// 4. Board number ASCENDING
// ============================================================================

final eventGamesProvider = FutureProvider.autoDispose.family<
  List<Games>,
  String
>((ref, eventId) async {
  // Keep data cached for 2 minutes after scrolling out of view,
  // then dispose to free RAM (PGN strings, player data, etc.)
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);

  final groupBroadcastRepo = ref.read(groupBroadcastRepositoryProvider);
  final tourRepository = ref.read(tourRepositoryProvider);
  final gamesStorage = ref.read(gamesLocalStorage);

  // ── 1. Fetch all tours for this event ──
  List<Tour> eventTours = [];
  try {
    eventTours = await tourRepository.getTourByGroupId(eventId);
  } catch (e) {
    debugPrint('[ForYou] Error fetching tours: $e');
  }

  // ── 2. Order tours deterministically ──
  // Live tours first, then by avgElo descending, then stable original order.
  if (eventTours.isNotEmpty) {
    final liveTourIds =
        ref.read(liveTourIdProvider).valueOrNull ?? <String>[];

    // Capture original indices for stable tie-breaking
    final originalOrder = {
      for (int i = 0; i < eventTours.length; i++) eventTours[i].id: i,
    };

    eventTours.sort((a, b) {
      final aLive = liveTourIds.contains(a.id) ? 0 : 1;
      final bLive = liveTourIds.contains(b.id) ? 0 : 1;
      if (aLive != bLive) return aLive.compareTo(bLive);

      final aElo = a.avgElo ?? 0;
      final bElo = b.avgElo ?? 0;
      if (aElo != bElo) return bElo.compareTo(aElo);

      return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
    });

    debugPrint(
      '[ForYou] Ordered ${eventTours.length} tours for event $eventId: '
      '${eventTours.map((t) => '"${t.name}" (elo:${t.avgElo}, live:${liveTourIds.contains(t.id)})').join(', ')}',
    );
  }

  // Build the list of tour IDs to fetch games from
  List<String> tourIdsToFetch = eventTours.map((t) => t.id).toList();
  if (tourIdsToFetch.isEmpty) {
    try {
      tourIdsToFetch = await groupBroadcastRepo.getTourIdsForGroupBroadcast(
        eventId,
      );
    } catch (e) {
      debugPrint('[ForYou] Error fetching tour IDs: $e');
    }
  }
  // Final fallback: use eventId as a tour ID
  if (tourIdsToFetch.isEmpty) {
    tourIdsToFetch = [eventId];
  }

  // ── 3. Fetch and filter started games from EVERY tour ──
  // Always use refresh() to get fresh data from network for For You tab.
  // This ensures we see new rounds immediately when they start.
  final allStartedGames = <Games>[];
  for (final tourId in tourIdsToFetch) {
    try {
      final games = await gamesStorage.refresh(tourId);
      for (final game in games) {
        if (_hasActuallyStarted(game) &&
            game.players != null &&
            game.players!.length >= 2) {
          allStartedGames.add(game);
        }
      }
    } catch (e) {
      debugPrint('[ForYou] Error fetching games for tour $tourId: $e');
    }
  }

  if (allStartedGames.isEmpty) {
    debugPrint('[ForYou] No games found for event $eventId');
    return [];
  }

  debugPrint(
    '[ForYou] Collected ${allStartedGames.length} started games across '
    '${tourIdsToFetch.length} tours for event $eventId',
  );

  // ── 4. Aggregate pin IDs from ALL tours ──
  final pinnedIds = <String>[];
  final seenPins = <String>{};
  for (final tourId in tourIdsToFetch) {
    try {
      final pinState = ref.read(gamesPinprovider(tourId));
      for (final pinId in pinState.allPins) {
        if (seenPins.add(pinId)) {
          pinnedIds.add(pinId);
        }
      }
    } catch (e) {
      // Pin provider might not be initialized for some tours
    }
  }

  // ── 5. Collect format strings and select games ──
  final formatStrings = eventTours.map((t) => t.info.format).toList();

  final result = selectForYouEventGames(
    allStartedGames: allStartedGames,
    pinnedIds: pinnedIds,
    formatStrings: formatStrings,
  );

  debugPrint(
    '[ForYou] Selected ${result.length} games for event $eventId '
    '(from ${allStartedGames.length} started across ${tourIdsToFetch.length} tours)',
  );
  return result;
});

/// Game must have actual moves OR be finished
/// This filters out games from unstarted rounds that have status='*' but no moves
/// Note: We don't check pgn.isNotEmpty because future games have PGN headers (~700 chars)
/// but no actual moves. Only lastMove and lastMoveTime indicate actual play.
bool _hasActuallyStarted(Games game) {
  final hasMoves =
      (game.lastMove?.isNotEmpty ?? false) || game.lastMoveTime != null;
  final isFinished =
      game.status == '1-0' ||
      game.status == '0-1' ||
      game.status == '1/2-1/2' ||
      game.status == '½-½';
  return hasMoves || isFinished;
}

/// Detects if an event is a 1v1 match format (e.g., "12-game Match").
/// Returns true when the tour format string contains "match" (case-insensitive)
/// AND there are at most 2 unique players among the started games.
bool _isMatchFormatEvent(String? formatString, List<Games> games) {
  if (formatString == null || formatString.isEmpty || games.isEmpty) {
    return false;
  }
  if (!formatString.toLowerCase().contains('match')) return false;

  final players = <String>{};
  for (final game in games) {
    final gamePlayers = game.players;
    if (gamePlayers == null) continue;
    for (final p in gamePlayers) {
      players.add(p.name);
      if (players.length > 2) return false; // early exit
    }
  }
  return players.length == 2;
}

/// Sorts games using the same algorithm as the Games tab:
/// 1. Pinned games first (preserving pin order)
/// 2. Round number DESCENDING
/// 3. Game number DESCENDING
/// 4. Board number ASCENDING
List<Games> _sortGamesLikeGamesTab(List<Games> games, List<String> pinnedIds) {
  if (games.isEmpty) return [];

  // Pre-parse round/game numbers to avoid repeated regex during sort
  final gameInfo = <String, (int, int)>{};
  for (final game in games) {
    gameInfo[game.id] = (
      _extractRoundNumber(game.roundSlug),
      _extractGameNumber(game.roundSlug),
    );
  }

  final sortedGames = List<Games>.from(games);
  sortedGames.sort((a, b) {
    // 1. Pinned games first (preserving pin order)
    final aPinned = pinnedIds.contains(a.id);
    final bPinned = pinnedIds.contains(b.id);
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;

    // If both are pinned, preserve pin order
    if (aPinned && bPinned) {
      final aIndex = pinnedIds.indexOf(a.id);
      final bIndex = pinnedIds.indexOf(b.id);
      if (aIndex != bIndex) return aIndex.compareTo(bIndex);
    }

    final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
    final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

    // 2. Sort by round number DESCENDING (latest round first)
    if (roundA != roundB) return roundB.compareTo(roundA);

    // 3. Within same round, sort by game number DESCENDING
    if (gameA != gameB) return gameB.compareTo(gameA);

    // 4. Finally, sort by board number ASCENDING
    final aBoard = a.boardNr, bBoard = b.boardNr;
    if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
    if (aBoard != null) return -1;
    if (bBoard != null) return 1;
    return 0;
  });

  return sortedGames;
}

int _extractRoundNumber(String roundSlug) {
  final slug = roundSlug.toLowerCase();

  // Named knockout stages — ranked above any numbered round.
  // Check more-specific names first to avoid substring false-positives.
  if (slug.contains('final') &&
      !slug.contains('quarter') &&
      !slug.contains('semi')) {
    return 10000;
  }
  if (slug.contains('semifinal') || slug.contains('semi-final')) {
    return 9000;
  }
  if (slug.contains('quarterfinal') || slug.contains('quarter-final')) {
    return 8000;
  }

  final match =
      RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
      RegExp(r'(\d+)').firstMatch(roundSlug);
  return int.tryParse(match?.group(1) ?? '0') ?? 0;
}

int _extractGameNumber(String roundSlug) {
  final match = RegExp(
    r'game-?(\d+)',
    caseSensitive: false,
  ).firstMatch(roundSlug);
  return int.tryParse(match?.group(1) ?? '0') ?? 0;
}

// ============================================================================
// EVENT-LEVEL GAME SELECTOR — FILLS UP TO kGamesPerEvent FROM ALL TOURS
// ============================================================================

/// Pure selector: picks up to [kGamesPerEvent] started games from a combined
/// pool of all tours in an event.
///
/// - [allStartedGames]: all started games from every tour, already filtered
///   by [_hasActuallyStarted] and having >= 2 players.
/// - [pinnedIds]: aggregated pin IDs from all tours (first-seen order, deduped).
/// - [formatStrings]: format strings from all tours in the event (used to
///   detect match format when ANY tour is a 1v1 match).
///
/// For match-format events: sort all games and take the first 4.
/// For normal events: take from the primary round (most recent activity) first,
/// then fill the deficit from remaining rounds ordered by recency.
@visibleForTesting
List<Games> selectForYouEventGames({
  required List<Games> allStartedGames,
  required List<String> pinnedIds,
  required List<String?> formatStrings,
}) {
  if (allStartedGames.isEmpty) return [];

  // Match format: check if ANY tour triggers match detection with the
  // combined game pool. _isMatchFormatEvent already returns false when
  // there are >2 unique players, so multi-tour events with different
  // players correctly fall through to the normal path.
  final isMatch = formatStrings.any(
    (fmt) => _isMatchFormatEvent(fmt, allStartedGames),
  );

  if (isMatch) {
    final sorted = _sortGamesLikeGamesTab(allStartedGames, pinnedIds);
    return sorted.take(kGamesPerEvent).toList();
  }

  // --- Normal (non-match) path ---

  // 1. Compute per-round recency: max activity timestamp per roundId.
  //    Fallback chain: lastMoveTime > gameDay > dateStart.
  final roundRecency = <String, DateTime>{};
  for (final game in allStartedGames) {
    final time = game.lastMoveTime ?? game.gameDay ?? game.dateStart;
    if (time == null) continue;
    final existing = roundRecency[game.roundId];
    if (existing == null || time.isAfter(existing)) {
      roundRecency[game.roundId] = time;
    }
  }

  // Sort round IDs by recency descending
  final roundsByRecency = roundRecency.keys.toList()
    ..sort((a, b) => roundRecency[b]!.compareTo(roundRecency[a]!));

  if (roundsByRecency.isEmpty) {
    // No timestamps at all — just sort everything and take 4
    final sorted = _sortGamesLikeGamesTab(allStartedGames, pinnedIds);
    return sorted.take(kGamesPerEvent).toList();
  }

  final primaryRoundId = roundsByRecency.first;

  // 2. Take games from the primary round first
  final primaryRoundGames =
      allStartedGames.where((g) => g.roundId == primaryRoundId).toList();
  final sortedPrimary = _sortGamesLikeGamesTab(primaryRoundGames, pinnedIds);
  final result = sortedPrimary.take(kGamesPerEvent).toList();

  if (result.length >= kGamesPerEvent) return result;

  // 3. Fill deficit from remaining rounds (by recency descending)
  final selectedIds = result.map((g) => g.id).toSet();

  for (final roundId in roundsByRecency.skip(1)) {
    if (result.length >= kGamesPerEvent) break;

    final roundGames = allStartedGames
        .where((g) => g.roundId == roundId && !selectedIds.contains(g.id))
        .toList();
    final sortedRound = _sortGamesLikeGamesTab(roundGames, pinnedIds);

    for (final game in sortedRound) {
      if (result.length >= kGamesPerEvent) break;
      if (selectedIds.add(game.id)) {
        result.add(game);
      }
    }
  }

  return result;
}

// ============================================================================
// LIVE ROUND WATCHER - DETECTS ROUND STARTS FOR ALL FOR YOU EVENTS
// ============================================================================

/// Tracks the last known set of live round IDs to detect changes
/// Persists across provider rebuilds to properly detect additions
final _lastKnownLiveRoundsProvider = StateProvider<Set<String>>((ref) => {});

// ============================================================================
// LIVE GAME WATCHER - AUTO-REFRESH WHEN GAMES FINISH OR ROUNDS START
// ============================================================================

/// Watches the status of displayed games and returns updated list
/// When a live game finishes OR a new round starts, it automatically re-fetches
final forYouEventGamesWithAutoRefreshProvider = Provider.autoDispose.family<
  AsyncValue<List<Games>>,
  String
>((ref, eventId) {
  // Watch the base games provider
  final gamesAsync = ref.watch(eventGamesProvider(eventId));

  // Listen for live round changes - this triggers refresh when new rounds start
  // Using listen instead of watch to get previous value for comparison
  ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (
    previous,
    current,
  ) {
    final currRounds = current.valueOrNull;
    if (currRounds == null) return;

    final currSet = currRounds.toSet();
    final lastKnown = ref.read(_lastKnownLiveRoundsProvider);

    // Only trigger refresh if we have a baseline AND new rounds were added
    // This prevents refresh on initial load
    if (lastKnown.isNotEmpty) {
      final newRounds = currSet.difference(lastKnown);
      if (newRounds.isNotEmpty) {
        debugPrint(
          '[ForYou] New rounds started: ${newRounds.length} rounds - refreshing games for event $eventId',
        );
        // Invalidate to re-fetch games with new round data
        Future.microtask(() {
          ref.invalidate(eventGamesProvider(eventId));
        });
      }
    }

    // Update baseline if changed
    if (!const SetEquality<String>().equals(currSet, lastKnown)) {
      Future.microtask(() {
        ref.read(_lastKnownLiveRoundsProvider.notifier).state = currSet;
      });
    }
  }, fireImmediately: true);

  return gamesAsync.when(
    data: (games) {
      // Find live games in current selection
      final liveGames =
          games.where((g) => g.status == '*' || g.status == 'ongoing').toList();

      // Watch game update streams for all live games.
      // Reuses gameUpdatesStreamProvider (same as liveGameCardProvider in game cards)
      // so Riverpod shares the provider instance — one Realtime channel per game
      // instead of two separate channels (status + updates).
      for (final game in liveGames) {
        final updatesAsync = ref.watch(gameUpdatesStreamProvider(game.id));
        updatesAsync.whenData((data) {
          final status = data?['status'] as String?;
          // If status changed to finished, invalidate to re-fetch
          if (status != null && _isFinishedStatus(status)) {
            debugPrint(
              '[ForYou] Game ${game.id} finished ($status), refreshing games for event $eventId',
            );
            // Use Future.microtask to avoid invalidating during build
            Future.microtask(() {
              ref.invalidate(eventGamesProvider(eventId));
            });
          }
        });
      }

      return AsyncValue.data(games);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

bool _isFinishedStatus(String status) {
  return status == '1-0' ||
      status == '0-1' ||
      status == '1/2-1/2' ||
      status == '½-½';
}

// ============================================================================
// BACKWARD COMPATIBILITY
// ============================================================================

final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>(
  (ref) {
    return const [];
  },
);

final forYouAnimatedGameIds = <String>{};
final forYouAnimatedEventIds = <String>{};
