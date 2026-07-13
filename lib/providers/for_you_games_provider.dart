import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/error_logger_provider.dart';
import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int kGamesPerEvent = 4;
const int _kPageSize = 20;
const Duration _kForYouStaleThreshold = Duration(minutes: 5);

enum ForYouVisibilityRefresh { topGames, fullFeed }

@visibleForTesting
ForYouVisibilityRefresh resolveForYouVisibilityRefresh({
  required DateTime? lastFeedRefreshAt,
  required DateTime now,
  required Duration maxFeedAge,
}) {
  if (lastFeedRefreshAt == null ||
      now.difference(lastFeedRefreshAt) >= maxFeedAge) {
    return ForYouVisibilityRefresh.fullFeed;
  }
  return ForYouVisibilityRefresh.topGames;
}

@visibleForTesting
List<GroupBroadcast> mergeMissingFavoriteCurrentBroadcasts({
  required List<GroupBroadcast> pageBroadcasts,
  required List<GroupBroadcast> favoriteBroadcasts,
  required List<String> favoriteIds,
}) {
  if (favoriteIds.isEmpty || favoriteBroadcasts.isEmpty) {
    return pageBroadcasts;
  }

  final existingIds = pageBroadcasts.map((broadcast) => broadcast.id).toSet();
  final favoriteById = {
    for (final broadcast in favoriteBroadcasts) broadcast.id: broadcast,
  };

  final missingFavorites = <GroupBroadcast>[];
  for (final favoriteId in favoriteIds) {
    if (existingIds.contains(favoriteId)) continue;
    final broadcast = favoriteById[favoriteId];
    if (broadcast == null) continue;
    missingFavorites.add(broadcast);
    existingIds.add(favoriteId);
  }

  if (missingFavorites.isEmpty) {
    return pageBroadcasts;
  }

  return [...missingFavorites, ...pageBroadcasts];
}

@visibleForTesting
Map<String, ForYouEventGamesSnapshot> mergeForYouTopGameSnapshots({
  required Map<String, ForYouEventGamesSnapshot> current,
  required Map<String, ForYouEventGamesSnapshot> incoming,
  required bool replace,
}) {
  var changed =
      replace && !setEquals(current.keys.toSet(), incoming.keys.toSet());
  final merged =
      replace
          ? <String, ForYouEventGamesSnapshot>{}
          : <String, ForYouEventGamesSnapshot>{...current};

  for (final entry in incoming.entries) {
    final existing = current[entry.key];
    if (existing != null &&
        areEquivalentForYouSnapshots(existing, entry.value)) {
      if (replace) merged[entry.key] = existing;
      continue;
    }

    merged[entry.key] = entry.value;
    changed = true;
  }

  return changed ? merged : current;
}

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
  bool _queuedFeedRefresh = false;
  DateTime? _lastRefreshAt;
  final Map<String, int> _sessionEventOrder = <String, int>{};
  int _nextSessionEventOrder = 0;
  bool _pendingFavoritePlayerOrderHydration = false;
  final Set<String> _handledUnknownLiveEventIds = <String>{};
  bool _isRefreshingTopGames = false;
  bool _liveFeedRefreshScheduled = false;
  bool _liveFeedRefreshPending = false;
  bool _resumeRefreshPending = false;
  final Set<String> _handledFinishedTopGameRefreshes = <String>{};

  ForYouNotifier(this.ref) : super(const ForYouState(isLoading: true)) {
    _setupListeners();
    _loadInitial();
  }

  void _setupListeners() {
    ref.listen<bool>(forYouSurfaceVisibleProvider, (_, isVisible) {
      if (!isVisible) return;
      if (_liveFeedRefreshPending) {
        _liveFeedRefreshPending = false;
        _resumeRefreshPending = false;
        _refreshFeedForLiveChange();
        return;
      }
      if (_resumeRefreshPending) {
        _resumeRefreshPending = false;
        unawaited(refreshIfStale());
      }
    });

    // Match the Current tab's behavior: when a tour transitions ongoing→live
    // (or live→completed), re-derive tourEventCategory on every existing card
    // so the _NextRoundLine flips from "starts in…" to "LIVE" without waiting
    // for a full refetch.
    ref.listen<AsyncValue<List<String>>>(liveGroupBroadcastIdsProvider, (
      _,
      next,
    ) {
      next.whenData((liveIds) {
        final liveCategoryChanged = _refreshLiveCategories(liveIds);
        final hasUnknownLiveEvent = _hasUnknownLiveEvents(liveIds);
        if (liveCategoryChanged || hasUnknownLiveEvent) {
          _refreshFeedForLiveChange();
        }
      });
    });

    ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (
      previous,
      next,
    ) {
      final liveRoundIds = next.valueOrNull;
      if (liveRoundIds == null) return;
      if (_sameStringSet(previous?.valueOrNull, liveRoundIds)) return;
      _refreshTopGamesAfterLiveSelectionChange();
    });

    ref.listen<AsyncValue<List<String>>>(liveTourIdProvider, (previous, next) {
      final liveTourIds = next.valueOrNull;
      if (liveTourIds == null) return;
      if (_sameStringSet(previous?.valueOrNull, liveTourIds)) return;
      _refreshTopGamesAfterLiveSelectionChange();
    });

    // Catch up on events that started while the app was backgrounded; the
    // 5-minute staleness gate keeps quick app switches cheap.
    ref.listen<int>(appResumedSignalProvider, (_, __) {
      if (ref.read(forYouSurfaceVisibleProvider)) {
        unawaited(refreshIfStale());
      } else {
        _resumeRefreshPending = true;
      }
    });

    ref.listen(favoritePlayersProviderNew, (_, next) {
      final shouldFinalizeOrder =
          _pendingFavoritePlayerOrderHydration &&
          _favoriteFideIdsFrom(
            next.valueOrNull ?? const <FavoritePlayer>[],
          ).isNotEmpty;

      if (next.hasValue && !shouldFinalizeOrder) {
        _pendingFavoritePlayerOrderHydration = false;
      }

      unawaited(
        _refreshVisibleFavoritePlayerCounts(
          finalizeOrderAfterRefresh: shouldFinalizeOrder,
        ),
      );
    });
  }

  /// A live event id we've never rendered usually means a brand-new event
  /// started while this feed was sitting on already-fetched pages — refetch
  /// page 0 so it can enter the list. Guarded per-id so ids that legitimately
  /// never enter the personalized feed (e.g. filtered out) don't refetch on
  /// every live-ids emission.
  bool _hasUnknownLiveEvents(List<String> liveIds) {
    if (state.isLoading || state.events.isEmpty) return false;

    final knownIds = state.events.map((event) => event.id).toSet();
    var hasNewUnknownId = false;
    for (final id in liveIds) {
      if (knownIds.contains(id)) continue;
      if (_handledUnknownLiveEventIds.add(id)) {
        hasNewUnknownId = true;
      }
    }
    return hasNewUnknownId;
  }

  bool _refreshLiveCategories(List<String> liveIds) {
    final current = state.events;
    if (current.isEmpty) return false;

    final updated = current.map((e) => e.withLiveIds(liveIds)).toList();

    bool changed = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].tourEventCategory != updated[i].tourEventCategory) {
        changed = true;
        break;
      }
    }
    if (!changed) return false;

    if (mounted) state = state.copyWith(events: updated);
    return true;
  }

  Future<void> _loadInitial() async {
    await _fetchPage(isInitial: true);
  }

  Future<void> refresh() async {
    if (_isFetching) {
      _queuedFeedRefresh = true;
      return;
    }
    _offset = 0;
    state = state.copyWith(isLoading: true, error: null);
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

  /// Refresh board membership when For You becomes visible. The heavier
  /// ordered event page is fetched only when the existing feed is older than
  /// [_kForYouStaleThreshold]. Live-set listeners handle in-place transitions.
  Future<void> refreshForVisibility({
    Duration maxFeedAge = _kForYouStaleThreshold,
  }) async {
    if (_isFetching ||
        state.isLoading ||
        _liveFeedRefreshPending ||
        _liveFeedRefreshScheduled) {
      return;
    }

    final refresh = resolveForYouVisibilityRefresh(
      lastFeedRefreshAt: _lastRefreshAt,
      now: DateTime.now(),
      maxFeedAge: maxFeedAge,
    );
    if (refresh == ForYouVisibilityRefresh.fullFeed) {
      await this.refresh();
      return;
    }

    await refreshVisibleTopGames();
  }

  void _refreshTopGamesAfterLiveSelectionChange() {
    // A new live round can change both preview membership and which existing
    // personalized event should bubble. Re-run the existing client ranking;
    // do not move user-specific stars/favorite-player logic into the RPC.
    _refreshFeedForLiveChange();
  }

  void _refreshFeedForLiveChange() {
    _sessionEventOrder.clear();
    _nextSessionEventOrder = 0;
    if (!ref.read(forYouSurfaceVisibleProvider)) {
      _liveFeedRefreshPending = true;
      return;
    }
    _liveFeedRefreshPending = false;
    if (_liveFeedRefreshScheduled) return;
    _liveFeedRefreshScheduled = true;
    Future.microtask(() {
      _liveFeedRefreshScheduled = false;
      if (!mounted) return;
      if (!ref.read(forYouSurfaceVisibleProvider)) {
        _liveFeedRefreshPending = true;
        return;
      }
      unawaited(refresh());
    });
  }

  Future<void> refreshVisibleTopGames() async {
    if (state.events.isEmpty) return;
    if (_isRefreshingTopGames) return;

    _isRefreshingTopGames = true;
    try {
      final visibleEvents = _topGamesRefreshCandidates(state.events);
      if (visibleEvents.isNotEmpty) {
        await _prefetchTopGames(
          visibleEvents,
          replace: false,
          refreshFavoritePlayerCounts: false,
        );
      }
    } finally {
      _isRefreshingTopGames = false;
    }
  }

  Future<void> refreshTopGamesForEvent(
    String eventId, {
    String? finishedGameId,
    String? finishedStatus,
  }) async {
    if (eventId.isEmpty) return;

    final normalizedFinishedStatus = finishedStatus?.trim();
    if (finishedGameId != null &&
        finishedGameId.isNotEmpty &&
        normalizedFinishedStatus != null &&
        normalizedFinishedStatus.isNotEmpty) {
      final refreshKey = '$eventId:$finishedGameId:$normalizedFinishedStatus';
      if (!_handledFinishedTopGameRefreshes.add(refreshKey)) {
        return;
      }
    }

    GroupEventCardModel? model;
    for (final event in state.events) {
      if (event.id == eventId) {
        model = event;
        break;
      }
    }
    if (model == null) return;

    await _prefetchTopGames(
      [model],
      replace: false,
      refreshFavoritePlayerCounts: false,
    );
  }

  List<GroupEventCardModel> _topGamesRefreshCandidates(
    List<GroupEventCardModel> events,
  ) {
    if (events.isEmpty) return const <GroupEventCardModel>[];

    final cachedSnapshots = ref.read(forYouTopGamesSnapshotCacheProvider);
    return events
        .where((event) {
          if (event.eventSource != EventSource.lichessBroadcast) {
            return false;
          }
          if (event.tourEventCategory == TourEventCategory.completed) {
            return false;
          }
          if (event.tourEventCategory == TourEventCategory.live ||
              event.tourEventCategory == TourEventCategory.ongoing) {
            return true;
          }
          return cachedSnapshots[event.id]?.hasGames ?? false;
        })
        .toList(growable: false);
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

      final minElo = appliedFilters.minElo;
      final maxElo = appliedFilters.maxElo;
      final hasEloFilter = appliedFilters.hasEloFilter;

      // Query Supabase with filters
      final repo = ref.read(groupBroadcastRepositoryProvider);

      final filteredBroadcasts = await repo.getForYouGroupBroadcasts(
        limit: _kPageSize,
        offset: _offset,
        timeControlFilters: formatFilters.isNotEmpty ? formatFilters : null,
        minElo: hasEloFilter ? minElo : null,
        maxElo: hasEloFilter ? maxElo : null,
        statusFilters: statusFilters.isNotEmpty ? statusFilters : null,
      );
      final dbHasMore = filteredBroadcasts.length >= _kPageSize;
      _offset += filteredBroadcasts.length;

      debugPrint(
        '[ForYou] Fetched ${filteredBroadcasts.length} from RPC '
        '(offset: $_offset, filters: format=$formatFilters, '
        'status=$statusFilters, elo=$hasEloFilter)',
      );

      // Prefer cached live IDs so For You can render after app resume even
      // while the realtime settings stream is reconnecting.
      final liveIds = await _getLiveIdsSnapshot();

      // Convert to models
      final models =
          filteredBroadcasts
              .map((b) => GroupEventCardModel.fromGroupBroadcast(b, liveIds))
              .toList();

      await _prefetchTopGames(models, replace: isInitial);

      // Bail out if the notifier was disposed while we were awaiting (e.g.
      // hot restart, or the tab/provider being torn down mid-fetch). Writing
      // `state` after dispose throws "used after dispose".
      if (!mounted) return;

      // Update state
      if (isInitial) {
        final previousEventIds = state.events
            .map((event) => event.id)
            .toList(growable: false);
        final nextEventIds = models
            .map((event) => event.id)
            .toList(growable: false);
        if (previousEventIds.isNotEmpty &&
            !_sameStringSet(previousEventIds, nextEventIds)) {
          // A newly eligible event must enter through the existing
          // user-specific star/favorite-player ranking, not be appended after
          // the session-stable cards.
          _sessionEventOrder.clear();
          _nextSessionEventOrder = 0;
        }
        state = ForYouState(
          events: _sortPageOnceForSession(models),
          isLoading: false,
          hasMore: dbHasMore,
        );
        _lastRefreshAt = DateTime.now();
        _maybeFinalizePendingFavoritePlayerOrder();
      } else {
        final existingIds = state.events.map((event) => event.id).toSet();
        final newModels =
            models.where((event) => !existingIds.contains(event.id)).toList();
        final sortedNewModels = _sortPageOnceForSession(newModels);
        state = state.copyWith(
          events: [...state.events, ...sortedNewModels],
          hasMore: dbHasMore,
        );
        _maybeFinalizePendingFavoritePlayerOrder();
      }
    } catch (e, stack) {
      debugPrint('[ForYou] Error: $e');
      debugPrint('[ForYou] Stack: $stack');
      _logErrorToSentry(e, stack);
      if (mounted) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    } finally {
      _isFetching = false;
      if (_queuedFeedRefresh && mounted) {
        _queuedFeedRefresh = false;
        Future.microtask(refresh);
      }
    }
  }

  List<GroupEventCardModel> _sortLikeCurrentTab(
    List<GroupEventCardModel> models,
  ) {
    return ref
        .read(tournamentSortingServiceProvider)
        .sortAllTours(
          models,
          eventFavoritePlayersMap: ref.read(eventFavoritePlayersCacheProvider),
        );
  }

  List<GroupEventCardModel> _sortPageOnceForSession(
    List<GroupEventCardModel> models,
  ) {
    if (models.isEmpty) return models;

    final knownEvents = <GroupEventCardModel>[];
    final newEvents = <GroupEventCardModel>[];
    for (final model in models) {
      if (_sessionEventOrder.containsKey(model.id)) {
        knownEvents.add(model);
      } else {
        newEvents.add(model);
      }
    }

    knownEvents.sort(
      (a, b) => _sessionEventOrder[a.id]!.compareTo(_sessionEventOrder[b.id]!),
    );

    final sortedNewEvents = _sortLikeCurrentTab(newEvents);
    for (final event in sortedNewEvents) {
      _sessionEventOrder[event.id] = _nextSessionEventOrder++;
    }

    return [...knownEvents, ...sortedNewEvents];
  }

  void _logErrorToSentry(dynamic error, StackTrace stackTrace) {
    unawaited(ref.read(errorLoggerProvider).logError(error, stackTrace));
  }

  Future<List<String>> _getLiveIdsSnapshot() async {
    final cached = ref.read(liveGroupBroadcastIdsProvider).valueOrNull;
    if (cached != null) return cached;

    try {
      return await ref.read(liveGroupBroadcastIdsProvider.future);
    } catch (e, stack) {
      debugPrint(
        '[ForYou] liveGroupBroadcastIdsProvider failed, falling back to empty list: $e',
      );
      debugPrint('[ForYou] Live IDs stack: $stack');
      _logErrorToSentry(e, stack);
      return const <String>[];
    }
  }

  Future<void> _prefetchTopGames(
    List<GroupEventCardModel> models, {
    required bool replace,
    bool refreshFavoritePlayerCounts = true,
  }) async {
    final notifier = ref.read(forYouTopGamesSnapshotCacheProvider.notifier);

    if (models.isEmpty) {
      if (replace) notifier.state = const <String, ForYouEventGamesSnapshot>{};
      return;
    }

    final eventIds = models
        .map((model) => model.id)
        .where((eventId) => eventId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (eventIds.isEmpty) {
      if (replace) notifier.state = const <String, ForYouEventGamesSnapshot>{};
      return;
    }

    final gameRepository = ref.read(gameRepositoryProvider);
    final prefetchResults = await Future.wait<Object?>([
      gameRepository.getForYouTopGamesByEventIds(
        eventIds: eventIds,
        boardsPerEvent: kGamesPerEvent,
      ),
      if (refreshFavoritePlayerCounts)
        _loadFavoritePlayerMatches(
          gameRepository: gameRepository,
          eventIds: eventIds,
          allowOrderHydrationFinalize: replace && _sessionEventOrder.isEmpty,
        ),
    ]);

    final gamesByEventId = prefetchResults[0]! as Map<String, List<Games>>;
    if (refreshFavoritePlayerCounts) {
      final favoritePlayerMatchesByEventId =
          prefetchResults[1]! as Map<String, List<int>>;
      _cacheFavoritePlayerMatches(
        eventIds: eventIds,
        matchesByEventId: favoritePlayerMatchesByEventId,
      );
    }

    if (!mounted) return;

    final snapshots = <String, ForYouEventGamesSnapshot>{
      for (final model in models)
        model.id: buildForYouTopGamesSnapshot(
          eventId: model.id,
          games: gamesByEventId[model.id] ?? const <Games>[],
          maxGames: kGamesPerEvent,
        ),
    };

    final merged = mergeForYouTopGameSnapshots(
      current: notifier.state,
      incoming: snapshots,
      replace: replace,
    );
    if (!identical(merged, notifier.state)) {
      notifier.state = merged;
    }
  }

  Future<void> _refreshVisibleFavoritePlayerCounts({
    bool finalizeOrderAfterRefresh = false,
  }) async {
    final eventIds = state.events
        .map((event) => event.id)
        .where((eventId) => eventId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (eventIds.isEmpty) return;

    final matchesByEventId = await _loadFavoritePlayerMatches(
      gameRepository: ref.read(gameRepositoryProvider),
      eventIds: eventIds,
    );
    if (!mounted) return;

    _cacheFavoritePlayerMatches(
      eventIds: eventIds,
      matchesByEventId: matchesByEventId,
    );

    if (finalizeOrderAfterRefresh) {
      _finalizeSessionOrderAfterFavoriteHydration();
    }
  }

  Future<Map<String, List<int>>> _loadFavoritePlayerMatches({
    required GameRepository gameRepository,
    required List<String> eventIds,
    bool allowOrderHydrationFinalize = false,
  }) async {
    try {
      final favoriteFideIds = await _favoriteFideIdsSnapshot(
        allowOrderHydrationFinalize: allowOrderHydrationFinalize,
      );
      if (favoriteFideIds.isEmpty) {
        return <String, List<int>>{};
      }

      return await gameRepository.getForYouFavoritePlayerFideIdsByEventIds(
        eventIds: eventIds,
        favoriteFideIds: favoriteFideIds,
      );
    } catch (e, stack) {
      debugPrint('[ForYou] Favorite player count prefetch failed: $e');
      debugPrint('[ForYou] Favorite player count stack: $stack');
      _logErrorToSentry(e, stack);
      return <String, List<int>>{};
    }
  }

  Future<List<int>> _favoriteFideIdsSnapshot({
    bool allowOrderHydrationFinalize = false,
  }) async {
    final favoritePlayersState = ref.read(favoritePlayersProviderNew);
    final loadedFavorites = favoritePlayersState.valueOrNull;
    if (loadedFavorites != null) {
      return _favoriteFideIdsFrom(loadedFavorites);
    }

    final favorites = await ref
        .read(favoritePlayersProviderNew.future)
        .timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () {
            if (allowOrderHydrationFinalize) {
              _pendingFavoritePlayerOrderHydration = true;
            }
            return const <FavoritePlayer>[];
          },
        );

    return _favoriteFideIdsFrom(favorites);
  }

  void _cacheFavoritePlayerMatches({
    required List<String> eventIds,
    required Map<String, List<int>> matchesByEventId,
  }) {
    final cacheEntries = <String, EventFavoritePlayers>{};
    for (final eventId in eventIds) {
      final fideIds = matchesByEventId[eventId] ?? const <int>[];
      cacheEntries[eventId] = EventFavoritePlayers(
        count: fideIds.length,
        fideIds: List<int>.unmodifiable(fideIds),
      );
    }

    ref
        .read(eventFavoritePlayersCacheProvider.notifier)
        .updateCacheBatch(cacheEntries);
  }

  void _finalizeSessionOrderAfterFavoriteHydration() {
    if (!_pendingFavoritePlayerOrderHydration || state.events.isEmpty) return;

    final sortedEvents = _sortLikeCurrentTab(state.events);
    _sessionEventOrder
      ..clear()
      ..addEntries(
        sortedEvents.indexed.map((entry) => MapEntry(entry.$2.id, entry.$1)),
      );
    _nextSessionEventOrder = sortedEvents.length;
    _pendingFavoritePlayerOrderHydration = false;

    if (mounted) {
      state = state.copyWith(events: sortedEvents);
    }
  }

  void _maybeFinalizePendingFavoritePlayerOrder() {
    if (!_pendingFavoritePlayerOrderHydration || state.events.isEmpty) return;

    final favoriteFideIds = _favoriteFideIdsFrom(
      ref.read(favoritePlayersProviderNew).valueOrNull ??
          const <FavoritePlayer>[],
    );
    if (favoriteFideIds.isEmpty) return;

    unawaited(
      _refreshVisibleFavoritePlayerCounts(finalizeOrderAfterRefresh: true),
    );
  }
}

List<int> _favoriteFideIdsFrom(Iterable<FavoritePlayer> favorites) {
  final fideIds = <int>{};
  for (final favorite in favorites) {
    final fideId = int.tryParse(favorite.fideId ?? '');
    if (fideId != null && fideId > 0) {
      fideIds.add(fideId);
    }
  }
  return fideIds.toList(growable: false);
}

bool _sameStringSet(List<String>? previous, List<String> next) {
  if (previous == null || previous.length != next.length) return false;
  final previousSet = previous.toSet();
  if (previousSet.length != next.toSet().length) return false;
  for (final id in next) {
    if (!previousSet.contains(id)) return false;
  }
  return true;
}

final forYouEventsProvider =
    StateNotifierProvider.autoDispose<ForYouNotifier, ForYouState>((ref) {
      ref.keepAlive();
      return ForYouNotifier(ref);
    });

/// True only while the personalized For You surface is the selected tab on the
/// current foreground route. The notifier keeps its cache alive, but expensive
/// catch-up work must wait for this signal instead of running behind any screen.
class ForYouSurfaceVisibilityNotifier extends StateNotifier<bool> {
  ForYouSurfaceVisibilityNotifier() : super(false);

  Object? _visibleOwner;

  void publish({required Object owner, required bool isVisible}) {
    if (!mounted) return;

    if (isVisible) {
      _visibleOwner = owner;
      if (!state) state = true;
      return;
    }

    // A disposed widget may publish its final hidden state after a replacement
    // has already mounted. Only the current owner is allowed to hide the
    // shared surface in that case.
    if (!identical(_visibleOwner, owner)) return;
    _visibleOwner = null;
    if (state) state = false;
  }
}

final forYouSurfaceVisibleProvider =
    StateNotifierProvider<ForYouSurfaceVisibilityNotifier, bool>(
      (ref) => ForYouSurfaceVisibilityNotifier(),
    );

final forYouTopGamesSnapshotCacheProvider =
    StateProvider<Map<String, ForYouEventGamesSnapshot>>(
      (ref) => const <String, ForYouEventGamesSnapshot>{},
    );

abstract class ForYouPinStorage {
  Future<List<String>> getPinnedGameIds(String tourId);

  Future<void> addPinnedGameId(String tourId, String gameId);

  Future<void> removePinnedGameId(String tourId, String gameId);

  Future<List<String>> getUnpinnedGameIds(String tourId);

  Future<void> addUnpinnedGameId(String tourId, String gameId);

  Future<void> removeUnpinnedGameId(String tourId, String gameId);
}

class _RiverpodForYouPinStorage implements ForYouPinStorage {
  const _RiverpodForYouPinStorage(this._ref);

  final Ref _ref;

  @override
  Future<List<String>> getPinnedGameIds(String tourId) {
    return _ref.read(pinGameLocalStorage).getPinnedGameIds(tourId);
  }

  @override
  Future<void> addPinnedGameId(String tourId, String gameId) {
    return _ref.read(pinGameLocalStorage).addPinnedGameId(tourId, gameId);
  }

  @override
  Future<void> removePinnedGameId(String tourId, String gameId) {
    return _ref.read(pinGameLocalStorage).removePinnedGameId(tourId, gameId);
  }

  @override
  Future<List<String>> getUnpinnedGameIds(String tourId) {
    return _ref.read(pinGameLocalStorage).getUnpinnedGameIds(tourId);
  }

  @override
  Future<void> addUnpinnedGameId(String tourId, String gameId) {
    return _ref.read(pinGameLocalStorage).addUnpinnedGameId(tourId, gameId);
  }

  @override
  Future<void> removeUnpinnedGameId(String tourId, String gameId) {
    return _ref.read(pinGameLocalStorage).removeUnpinnedGameId(tourId, gameId);
  }
}

final forYouPinStorageProvider = Provider<ForYouPinStorage>((ref) {
  return _RiverpodForYouPinStorage(ref);
});

abstract class ForYouPinAction {
  Future<void> togglePin({
    required String eventId,
    required String gameId,
    required String tourId,
  });
}

final forYouPinActionProvider = Provider.autoDispose<ForYouPinAction>(
  (ref) => _ForYouPinActionController(ref),
);

class _ForYouPinActionController implements ForYouPinAction {
  const _ForYouPinActionController(this._ref);

  final Ref _ref;

  @override
  Future<void> togglePin({
    required String eventId,
    required String gameId,
    required String tourId,
  }) async {
    final storage = _ref.read(forYouPinStorageProvider);
    final snapshot =
        _ref.read(forYouEventSnapshotProvider(eventId)).valueOrNull;
    final mode = resolvePinToggleMode(
      isManualPinned:
          snapshot?.manualPinnedIds.contains(gameId) ??
          (await storage.getPinnedGameIds(tourId)).contains(gameId),
      isAutoPinned: snapshot?.autoPinnedIds.contains(gameId) ?? false,
      isOverridden:
          snapshot?.unpinnedOverrideIds.contains(gameId) ??
          (await storage.getUnpinnedGameIds(tourId)).contains(gameId),
    );

    switch (mode) {
      case PinToggleMode.unpinManualOnly:
        await storage.removePinnedGameId(tourId, gameId);
        break;
      case PinToggleMode.unpinWithOverride:
        await Future.wait([
          storage.removePinnedGameId(tourId, gameId),
          storage.addUnpinnedGameId(tourId, gameId),
        ]);
        break;
      case PinToggleMode.repin:
        await Future.wait([
          storage.removeUnpinnedGameId(tourId, gameId),
          storage.addPinnedGameId(tourId, gameId),
        ]);
        break;
    }

    final selectedBroadcast = _ref.read(selectedBroadcastModelProvider);
    final selectedTourId =
        _ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id;

    if (selectedBroadcast?.id == eventId &&
        selectedTourId != null &&
        selectedTourId.isNotEmpty) {
      _ref.invalidate(gamesPinprovider(selectedTourId));
      _ref.invalidate(gamesTourScreenProvider);
    }

    bumpEventPinRefreshSignal(_ref, eventId);
  }
}

// ============================================================================
// LIVE GAME WATCHER - AUTO-REFRESH WHEN GAMES FINISH
// ============================================================================

/// Watches displayed live games so each visible For You section refreshes its
/// RPC-selected preview boards when a rendered live game finishes.
///
/// The card widgets consume their own live row data, but this wrapper keeps the
/// section subscribed to the same rendered live rows and refreshes the snapshot
/// as soon as a displayed game finishes.
final forYouEventGamesWithAutoRefreshProvider = Provider.autoDispose.family<
  AsyncValue<ForYouEventGamesSnapshot>,
  String
>((ref, eventId) {
  final snapshotAsync = ref.watch(forYouEventSnapshotProvider(eventId));

  return snapshotAsync.when(
    data: (snapshot) {
      final displayedGames = snapshot.visibleGames.take(kGamesPerEvent);
      final displayedLiveGames = displayedGames
          .where(shouldSubscribeToLiveGame)
          .toList(growable: false);

      if (displayedLiveGames.isNotEmpty) {
        final shouldWatchLiveFinishes = ref.watch(shouldStreamProvider);
        if (!shouldWatchLiveFinishes) {
          return AsyncValue.data(snapshot);
        }

        final watchedGameIds = displayedLiveGames
            .map((game) => game.gameId)
            .toList(growable: false);
        final updatesAsync = ref.watch(
          gameUpdatesBatchStreamProvider(
            LiveGamesBatchKey(
              scopeId: 'for_you:$eventId:${snapshot.tourId}',
              gameIds: displayedLiveGames.map((game) => game.gameId),
            ),
          ).select(
            (async) => async.whenData(
              (updates) => _LiveGameStatusProjection.fromUpdates(
                watchedGameIds,
                updates,
              ),
            ),
          ),
        );

        updatesAsync.whenData((updates) {
          for (final status in updates.statuses) {
            if (status.status != null && _isFinishedStatus(status.status!)) {
              Future.microtask(() {
                try {
                  ref
                      .read(forYouEventsProvider.notifier)
                      .refreshTopGamesForEvent(
                        eventId,
                        finishedGameId: status.gameId,
                        finishedStatus: status.status!,
                      );
                } on StateError {
                  // The section can be disposed while a stream event is queued.
                }
              });
            }
          }
        });
      }

      return AsyncValue.data(snapshot);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

@immutable
class _LiveGameStatusProjection {
  const _LiveGameStatusProjection(this.statuses);

  factory _LiveGameStatusProjection.fromUpdates(
    List<String> gameIds,
    Map<String, LiveGameUpdate> updates,
  ) {
    return _LiveGameStatusProjection(
      List<_LiveGameStatus>.unmodifiable(
        gameIds.map(
          (gameId) => _LiveGameStatus(gameId, updates[gameId]?.status),
        ),
      ),
    );
  }

  final List<_LiveGameStatus> statuses;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _LiveGameStatusProjection) return false;
    return listEquals(statuses, other.statuses);
  }

  @override
  int get hashCode => Object.hashAll(statuses);
}

@immutable
class _LiveGameStatus {
  const _LiveGameStatus(this.gameId, this.status);

  final String gameId;
  final String? status;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _LiveGameStatus &&
            other.gameId == gameId &&
            other.status == status;
  }

  @override
  int get hashCode => Object.hash(gameId, status);
}

/// Read-only snapshot alias for non-rendering code paths.
final forYouEventSnapshotProvider = Provider.autoDispose
    .family<AsyncValue<ForYouEventGamesSnapshot>, String>((ref, eventId) {
      final snapshot = ref.watch(
        forYouTopGamesSnapshotCacheProvider.select((cache) => cache[eventId]),
      );
      return snapshot == null
          ? const AsyncValue.loading()
          : AsyncValue.data(snapshot);
    });

bool _isFinishedStatus(String status) {
  return GameStatus.fromString(status).isFinished;
}

// ============================================================================
// BACKWARD COMPATIBILITY
// ============================================================================

final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>(
  (ref) {
    return const [];
  },
);
