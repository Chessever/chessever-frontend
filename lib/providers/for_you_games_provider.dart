import 'dart:async';

import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/error_logger_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_auto_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_selection_logic.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
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

    // When the user's favorite players change, recompute the visible
    // heart-count cache in one batch. For You cards consume this cache only,
    // avoiding an N-per-card fallback while preserving the same final UI.
    ref.listen(favoritePlayersProviderNew, (_, next) {
      if (!next.hasValue) return;
      ref.read(eventFavoritePlayersCacheProvider.notifier).clear();
      _prefetchHeartDataWithTimeout(state.events);
      bumpForYouEventsRefreshSignal(ref);
    });

    // Match the Current tab's behavior: when a tour transitions ongoing→live
    // (or live→completed), re-derive tourEventCategory on every existing card
    // so the _NextRoundLine flips from "starts in…" to "LIVE" without waiting
    // for a full refetch.
    ref.listen<AsyncValue<List<String>>>(liveGroupBroadcastIdsProvider, (
      _,
      next,
    ) {
      next.whenData(_refreshLiveCategories);
    });

    // Global signals that affect EVERY visible event's snapshot (auto-pin,
    // tour selection defaults, sign-in state, live transitions). Funnel them
    // through `forYouEventsRefreshProvider` so each `eventGamesProvider`
    // family entry only needs ONE listener instead of N. The single fan-out
    // here replaces 6×N per-event listens.
    ref.listen(favoritesVersionProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(countryDropdownProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(autoPinPreferencesProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(currentUserProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(liveTourIdProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
    ref.listen(liveRoundsIdProvider, (_, __) {
      bumpForYouEventsRefreshSignal(ref);
    });
  }

  void _refreshLiveCategories(List<String> liveIds) {
    final current = state.events;
    if (current.isEmpty) return;

    final updated = current.map((e) => e.withLiveIds(liveIds)).toList();

    bool changed = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i].tourEventCategory != updated[i].tourEventCategory) {
        changed = true;
        break;
      }
    }
    if (!changed) return;

    if (mounted) state = state.copyWith(events: updated);
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
    state = state.copyWith(isLoading: true, error: null);
    bumpForYouEventsRefreshSignal(ref);
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

      // Prefer cached live IDs so For You can render after app resume even
      // while the realtime settings stream is reconnecting.
      final liveIds = await _getLiveIdsSnapshot();

      // Fetch pages from DB. When status filters are active, a single page
      // may yield zero matches (e.g. no live events in the first 20 results).
      // Keep fetching until we have results or the DB is exhausted.
      List<GroupBroadcast> filteredBroadcasts = [];
      bool dbHasMore = true;

      do {
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

        dbHasMore = broadcasts.length >= _kPageSize;
        _offset += broadcasts.length;

        // Apply status filter (live/completed) - can't do in DB query
        if (statusFilters.isNotEmpty) {
          final filtered =
              broadcasts.where((tour) {
                final isLive = liveIds.contains(tour.id);
                return (statusFilters.contains('live') && isLive) ||
                    (statusFilters.contains('completed') && !isLive);
              }).toList();
          filteredBroadcasts.addAll(filtered);
        } else {
          filteredBroadcasts = broadcasts;
          break;
        }
      } while (filteredBroadcasts.isEmpty && dbHasMore);

      // Convert to models
      final models =
          filteredBroadcasts
              .map((b) => GroupEventCardModel.fromGroupBroadcast(b, liveIds))
              .toList();

      // Pre-fetch heart data in background — don't block page render.
      // This prevents For You from saturating the HTTP connection pool
      // and starving other tabs (e.g. Current) of network access.
      // 5s timeout prevents indefinite stalling if any provider hangs.
      _prefetchHeartDataWithTimeout(models);

      // Sort this batch (without heart data initially — will re-sort once heart data arrives)
      final sortedModels = await _sortModels(models);

      // Update state
      if (isInitial) {
        state = ForYouState(
          events: sortedModels,
          isLoading: false,
          hasMore: dbHasMore,
        );
        _lastRefreshAt = DateTime.now();
      } else {
        state = state.copyWith(
          events: [...state.events, ...sortedModels],
          hasMore: dbHasMore,
        );
      }
    } catch (e, stack) {
      debugPrint('[ForYou] Error: $e');
      debugPrint('[ForYou] Stack: $stack');
      _logErrorToSentry(e, stack);
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      _isFetching = false;
    }
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

        // Match the legacy per-card provider behavior: if roster data is
        // absent/stale, derive favorite-player presence from games instead.
        if (eventPlayerFideIds.isEmpty) {
          eventPlayerFideIds.addAll(
            await _loadEventPlayerFideIdsFromGamesFallback(
              eventId: model.id,
              tours: tours,
            ),
          );
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

  void _prefetchHeartDataWithTimeout(List<GroupEventCardModel> models) {
    if (models.isEmpty) return;
    unawaited(
      _prefetchHeartData(models)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('[ForYou] _prefetchHeartData timed out after 5s');
            },
          )
          .then((_) {
            if (mounted) _reSortList();
          }),
    );
  }

  Future<Set<int>> _loadEventPlayerFideIdsFromGamesFallback({
    required String eventId,
    required List<Tour> tours,
  }) async {
    try {
      var tourIds = tours.map((tour) => tour.id).toList(growable: false);

      if (tourIds.isEmpty) {
        try {
          tourIds = await ref
              .read(groupBroadcastRepositoryProvider)
              .getTourIdsForGroupBroadcast(eventId);
        } catch (_) {
          tourIds = const <String>[];
        }
      }

      if (tourIds.isEmpty) {
        tourIds = [eventId];
      }

      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesFromTourIds(tourIds: tourIds, limit: 200, offset: 0);

      final fideIds = <int>{};
      for (final game in games) {
        final players = game.players;
        if (players == null || players.isEmpty) continue;
        for (final player in players) {
          if (player.fideId > 0) {
            fideIds.add(player.fideId);
          }
        }
      }
      return fideIds;
    } catch (e) {
      debugPrint('[ForYou] Error in heart fallback for $eventId: $e');
      return const <int>{};
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

final currentTournamentDetailSelectedTourIdProvider = Provider<String?>((ref) {
  return ref.watch(
    tourDetailScreenProvider.select(
      (value) => value.valueOrNull?.aboutTourModel.id,
    ),
  );
});

final currentSelectedTourIdForEventProvider = Provider.autoDispose
    .family<String?, String>((ref, eventId) {
      final isSelectedEvent = ref.watch(
        selectedBroadcastModelProvider.select(
          (broadcast) => broadcast?.id == eventId,
        ),
      );

      if (!isSelectedEvent) {
        return null;
      }

      return ref.watch(currentTournamentDetailSelectedTourIdProvider);
    });

class _ForYouComputedPinState {
  const _ForYouComputedPinState({
    required this.manualPins,
    required this.autoPins,
    required this.unpinnedOverrides,
    required this.effectivePins,
  });

  final List<String> manualPins;
  final List<String> autoPins;
  final List<String> unpinnedOverrides;
  final List<String> effectivePins;
}

class _ForYouResolvedEventData {
  const _ForYouResolvedEventData({
    required this.selectedTour,
    required this.eventTours,
    required this.selectedTourRounds,
    required this.roundsByTourId,
    required this.selectedTourGames,
    required this.gamesByTourId,
    required this.liveRoundIds,
  });

  final Tour selectedTour;
  final List<Tour> eventTours;
  final List<Round> selectedTourRounds;
  final Map<String, List<Round>> roundsByTourId;
  final List<Games> selectedTourGames;
  final Map<String, List<Games>> gamesByTourId;
  final List<String> liveRoundIds;
}

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
// LAZY GAMES PER EVENT PROVIDER
// Mirrors the Games tab for the event's resolved default tour,
// then lets the UI render only the first 4 visible games.
// ============================================================================

final eventGamesProvider = StateNotifierProvider.autoDispose.family<
  _ForYouEventGamesController,
  AsyncValue<ForYouEventGamesSnapshot>,
  String
>((ref, eventId) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  final controller = _ForYouEventGamesController(ref: ref, eventId: eventId);

  ref.onCancel(controller.handleCancel);
  ref.onResume(controller.handleResume);

  // Per-event listeners only. Global signals (favorites version, country
  // dropdown, auto-pin prefs, current user, live tour id, live rounds id) are
  // funneled through `forYouEventsRefreshProvider` by `ForYouNotifier` — that
  // collapses N×6 family listens into 6 single listens + N event listens, a
  // ~6× reduction at typical list sizes.
  ref.listen(eventPinRefreshProvider(eventId), (_, __) {
    controller.requestRefresh();
  });
  ref.listen(forYouEventsRefreshProvider, (_, __) {
    controller.requestRefresh();
  });
  ref.listen(currentSelectedTourIdForEventProvider(eventId), (_, __) {
    controller.requestRefresh();
  });

  return controller;
});

class _ForYouEventGamesController
    extends StateNotifier<AsyncValue<ForYouEventGamesSnapshot>> {
  _ForYouEventGamesController({required this.ref, required this.eventId})
    : super(const AsyncValue.loading()) {
    requestRefresh();
  }

  final Ref ref;
  final String eventId;

  bool _isObserved = true;
  bool _isRefreshing = false;
  bool _queuedRefresh = false;

  void handleCancel() {
    _isObserved = false;
  }

  void handleResume() {
    _isObserved = true;
    if (_queuedRefresh || state.valueOrNull == null) {
      requestRefresh();
    }
  }

  void requestRefresh() {
    if (!mounted) {
      return;
    }

    if (!_isObserved) {
      _queuedRefresh = true;
      return;
    }

    if (_isRefreshing) {
      _queuedRefresh = true;
      return;
    }

    unawaited(_performRefreshLoop());
  }

  Future<void> _performRefreshLoop() async {
    if (_isRefreshing) {
      return;
    }

    _isRefreshing = true;
    try {
      do {
        _queuedRefresh = false;
        await _refreshOnce();
      } while (mounted && _isObserved && _queuedRefresh);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _refreshOnce() async {
    final previousSnapshot = state.valueOrNull;

    if (previousSnapshot == null && !state.isLoading) {
      state = const AsyncValue.loading();
    }

    Object? loadError;
    StackTrace? loadStack;

    try {
      final cachedSnapshot = await _computeForYouEventGamesSnapshot(
        ref: ref,
        eventId: eventId,
        loadGames: _safeGetGames,
      );
      // On cold start (no previous snapshot), only surface the cache result
      // when it actually contains renderable games. An empty cache result
      // would prematurely kill the shimmer while the network refresh below
      // is still in-flight.
      if (previousSnapshot == null && !cachedSnapshot.hasGames) {
        // Stay in loading — the network refresh below will resolve the state.
      } else {
        final currentSnapshot = state.valueOrNull;
        if (currentSnapshot == null ||
            !areEquivalentForYouSnapshots(currentSnapshot, cachedSnapshot)) {
          state = AsyncValue.data(cachedSnapshot);
        }
      }
    } catch (error, stackTrace) {
      loadError = error;
      loadStack = stackTrace;
      debugPrint('[ForYou] Cache-first snapshot failed for $eventId: $error');
    }

    try {
      final refreshedSnapshot = await _computeForYouEventGamesSnapshot(
        ref: ref,
        eventId: eventId,
        loadGames: _safeRefreshGames,
      );
      final currentSnapshot = state.valueOrNull;
      if (currentSnapshot == null ||
          !areEquivalentForYouSnapshots(currentSnapshot, refreshedSnapshot)) {
        state = AsyncValue.data(refreshedSnapshot);
      }
      return;
    } catch (error, stackTrace) {
      loadError ??= error;
      loadStack ??= stackTrace;
      debugPrint('[ForYou] Refreshed snapshot failed for $eventId: $error');
    }

    if (state.valueOrNull == null) {
      state = AsyncValue.error(loadError, loadStack);
    } else if (previousSnapshot != null && mounted) {
      state = AsyncValue.data(previousSnapshot);
    }
  }
}

typedef _GamesStorageLoader =
    Future<List<Games>> Function({
      required GamesLocalStorage gamesStorage,
      required String tourId,
    });

Future<ForYouEventGamesSnapshot> _computeForYouEventGamesSnapshot({
  required Ref ref,
  required String eventId,
  required _GamesStorageLoader loadGames,
}) async {
  final resolvedEventData = await _loadForYouResolvedEventData(
    ref: ref,
    eventId: eventId,
    loadGames: loadGames,
  );

  if (resolvedEventData == null) {
    return _emptyForYouEventGamesSnapshot(eventId);
  }

  final selectedTour = resolvedEventData.selectedTour;
  final eventTours = resolvedEventData.eventTours;
  final selectedTourRounds = resolvedEventData.selectedTourRounds;
  final roundsByTourId = resolvedEventData.roundsByTourId;
  final selectedTourGames = resolvedEventData.selectedTourGames;
  final gamesByTourId = resolvedEventData.gamesByTourId;
  final liveRoundIds = resolvedEventData.liveRoundIds;

  final isKnockout = isKnockoutTour(
    tour: selectedTour,
    games: selectedTourGames,
  );

  final gamesForAutoPin =
      isKnockout
          ? gamesByTourId.values
              .expand((games) => games)
              .map((game) {
                try {
                  return GamesTourModel.fromGame(game);
                } catch (_) {
                  return null;
                }
              })
              .whereType<GamesTourModel>()
              .toList()
          : sortGamesForGamesTab(games: selectedTourGames, pinnedIds: const []);

  final pinState = await _loadPinnedStateForEvent(
    ref: ref,
    relatedTourIds:
        isKnockout
            ? eventTours.map((tour) => tour.id).toList(growable: false)
            : [selectedTour.id],
    autoPinTourId: selectedTour.id,
    allRelevantGames: gamesForAutoPin,
  );

  final snapshot = buildForYouEventGamesSnapshot(
    eventId: eventId,
    selectedTour: selectedTour,
    eventTours: eventTours,
    selectedTourRounds: selectedTourRounds,
    roundsByTourId: roundsByTourId,
    selectedTourGames: selectedTourGames,
    gamesByTourId: gamesByTourId,
    liveRoundIds: liveRoundIds,
    pinnedIds: pinState.effectivePins,
    manualPinnedIds: pinState.manualPins,
    autoPinnedIds: pinState.autoPins,
    unpinnedOverrideIds: pinState.unpinnedOverrides,
  );

  debugPrint(
    '[ForYou] Snapshot for $eventId resolved to ${snapshot.tourId} '
    'with ${snapshot.visibleGames.length} visible Games-tab games',
  );
  return snapshot;
}

Future<_ForYouResolvedEventData?> _loadForYouResolvedEventData({
  required Ref ref,
  required String eventId,
  required _GamesStorageLoader loadGames,
}) async {
  final groupBroadcastRepo = ref.read(groupBroadcastRepositoryProvider);
  final gameRepository = ref.read(gameRepositoryProvider);
  final gamesStorage = ref.read(gamesLocalStorage);
  final roundRepository = ref.read(roundRepositoryProvider);
  final tourRepository = ref.read(tourRepositoryProvider);
  final liveTourIds = ref.read(liveTourIdProvider).valueOrNull ?? <String>[];
  final liveRoundIds = ref.read(liveRoundsIdProvider).valueOrNull ?? <String>[];

  final initialResults = await Future.wait<Object?>([
    _safeLoadEventTours(
      tourRepository: tourRepository,
      groupBroadcastRepo: groupBroadcastRepo,
      eventId: eventId,
    ),
    _safeLoadSavedTourId(ref: ref, eventId: eventId),
  ]);
  final eventTours = initialResults[0]! as List<Tour>;
  final savedTourId = initialResults[1] as String?;

  if (eventTours.isEmpty) {
    return null;
  }

  final tourModels = _buildEventTourModels(eventTours, liveTourIds);
  if (tourModels.isEmpty) {
    return null;
  }

  final currentSelectedTourId = ref.read(
    currentSelectedTourIdForEventProvider(eventId),
  );

  String? activityTourId;
  if (shouldLoadDeferredActivityTourId(
    tourModels: tourModels,
    currentSelectedId: currentSelectedTourId,
    savedTourId: savedTourId,
  )) {
    activityTourId = await _safeLoadActivityTourId(
      gameRepository: gameRepository,
      eventId: eventId,
      tourIds: tourModels.map((model) => model.tour.id).toList(growable: false),
    );
  }

  final selectedTour = selectDefaultTour(
    tourModels: tourModels,
    liveTourIds: liveTourIds,
    currentSelectedId: currentSelectedTourId,
    savedTourId: savedTourId,
    activityTourId: activityTourId,
  );

  final selectedTourData = await Future.wait<Object?>([
    loadGames(gamesStorage: gamesStorage, tourId: selectedTour.id),
    _safeLoadRounds(roundRepository: roundRepository, tourId: selectedTour.id),
  ]);
  final selectedTourGames = selectedTourData[0]! as List<Games>;
  final selectedTourRounds = selectedTourData[1]! as List<Round>;

  final isKnockout = isKnockoutTour(
    tour: selectedTour,
    games: selectedTourGames,
  );

  final gamesByTourId = <String, List<Games>>{
    selectedTour.id: selectedTourGames,
  };
  final roundsByTourId = <String, List<Round>>{
    selectedTour.id: selectedTourRounds,
  };

  if (isKnockout) {
    final siblingTours = eventTours
        .where((tour) => tour.id != selectedTour.id)
        .toList(growable: false);

    if (siblingTours.isNotEmpty) {
      final siblingTourIds = siblingTours
          .map((tour) => tour.id)
          .toList(growable: false);
      final siblingResults = await Future.wait<Object?>([
        Future.wait(
          siblingTours.map(
            (tour) => loadGames(gamesStorage: gamesStorage, tourId: tour.id),
          ),
        ),
        _safeLoadRoundsByTourIds(
          roundRepository: roundRepository,
          tourIds: siblingTourIds,
        ),
      ]);

      final siblingGames = siblingResults[0]! as List<List<Games>>;
      final siblingRoundsByTourId =
          siblingResults[1]! as Map<String, List<Round>>;

      for (var i = 0; i < siblingTours.length; i++) {
        final tourId = siblingTours[i].id;
        gamesByTourId[tourId] = siblingGames[i];
        roundsByTourId[tourId] =
            siblingRoundsByTourId[tourId] ?? const <Round>[];
      }
    }
  }

  return _ForYouResolvedEventData(
    selectedTour: selectedTour,
    eventTours: eventTours,
    selectedTourRounds: selectedTourRounds,
    roundsByTourId: roundsByTourId,
    selectedTourGames: selectedTourGames,
    gamesByTourId: gamesByTourId,
    liveRoundIds: liveRoundIds,
  );
}

ForYouEventGamesSnapshot _emptyForYouEventGamesSnapshot(String eventId) {
  return ForYouEventGamesSnapshot(
    eventId: eventId,
    tourId: '',
    visibleGames: const [],
    pinnedIds: const [],
  );
}

List<TourModel> _buildEventTourModels(
  List<Tour> tours,
  List<String> liveTourIds,
) {
  final now = DateTime.now();
  final models = <TourModel>[];

  for (final tour in tours) {
    if (tour.dates.isEmpty) {
      final status =
          liveTourIds.contains(tour.id)
              ? RoundStatus.live
              : RoundStatus.completed;
      models.add(TourModel(tour: tour, roundStatus: status));
      continue;
    }

    final status = calculateTourRoundStatus(
      tourId: tour.id,
      now: now,
      startDate: tour.dates.first,
      endDate: tour.dates.last,
      liveTourIds: liveTourIds,
    );
    models.add(TourModel(tour: tour, roundStatus: status));
  }

  return models;
}

Future<List<Games>> _safeRefreshGames({
  required GamesLocalStorage gamesStorage,
  required String tourId,
}) async {
  try {
    return await gamesStorage.refresh(tourId);
  } catch (e) {
    debugPrint('[ForYou] Error fetching games for tour $tourId: $e');
    return const <Games>[];
  }
}

Future<List<Games>> _safeGetGames({
  required GamesLocalStorage gamesStorage,
  required String tourId,
}) async {
  try {
    return await gamesStorage.getCachedGames(tourId);
  } catch (e) {
    debugPrint('[ForYou] Error reading cached games for tour $tourId: $e');
    return const <Games>[];
  }
}

Future<List<Tour>> _safeLoadEventTours({
  required TourRepository tourRepository,
  required GroupBroadcastRepository groupBroadcastRepo,
  required String eventId,
}) async {
  List<Tour> eventTours = [];

  try {
    eventTours = await tourRepository.getTourByGroupId(eventId);
  } catch (e) {
    debugPrint('[ForYou] Error fetching tours: $e');
  }

  if (eventTours.isEmpty) {
    try {
      final tourIds = await groupBroadcastRepo.getTourIdsForGroupBroadcast(
        eventId,
      );
      eventTours = await tourRepository.getToursByIds(tourIds);
    } catch (e) {
      debugPrint('[ForYou] Error fetching fallback tours: $e');
    }
  }

  return eventTours;
}

Future<String?> _safeLoadSavedTourId({
  required Ref ref,
  required String eventId,
}) async {
  try {
    return await ref.read(tourDetailRepoProvider).getSelectedTourId(eventId);
  } catch (e) {
    debugPrint('[ForYou] Error reading saved tour selection: $e');
    return null;
  }
}

Future<String?> _safeLoadActivityTourId({
  required GameRepository gameRepository,
  required String eventId,
  required List<String> tourIds,
}) async {
  try {
    return await gameRepository.getMostRelevantTourId(tourIds: tourIds);
  } catch (e) {
    debugPrint('[ForYou] Error resolving relevant tour for $eventId: $e');
    return null;
  }
}

Future<List<Round>> _safeLoadRounds({
  required RoundRepository roundRepository,
  required String tourId,
}) async {
  try {
    return await roundRepository.getRoundsByTourId(tourId);
  } catch (e) {
    debugPrint('[ForYou] Error fetching rounds for tour $tourId: $e');
    return const <Round>[];
  }
}

Future<Map<String, List<Round>>> _safeLoadRoundsByTourIds({
  required RoundRepository roundRepository,
  required List<String> tourIds,
}) async {
  try {
    return await roundRepository.getRoundsByTourIds(tourIds);
  } catch (e) {
    debugPrint('[ForYou] Error fetching rounds for tours $tourIds: $e');
    return <String, List<Round>>{
      for (final tourId in tourIds) tourId: const <Round>[],
    };
  }
}

Future<_ForYouComputedPinState> _loadPinnedStateForEvent({
  required Ref ref,
  required List<String> relatedTourIds,
  required String autoPinTourId,
  required List<GamesTourModel> allRelevantGames,
}) async {
  final pinResults = await Future.wait<Object?>([
    _loadManualPinsForTours(ref: ref, tourIds: relatedTourIds),
    _loadUnpinnedOverridesForTours(ref: ref, tourIds: relatedTourIds),
    _loadAutoPins(
      ref: ref,
      tourId: autoPinTourId,
      allRelevantGames: allRelevantGames,
    ),
  ]);
  final manualPins = pinResults[0]! as List<String>;
  final unpinnedOverrides = pinResults[1]! as List<String>;
  final autoPins = pinResults[2]! as List<String>;
  return _ForYouComputedPinState(
    manualPins: manualPins,
    autoPins: autoPins,
    unpinnedOverrides: unpinnedOverrides,
    effectivePins: mergeEffectivePins(
      manualPins: manualPins,
      autoPins: autoPins,
      unpinnedOverrides: unpinnedOverrides,
    ),
  );
}

@visibleForTesting
List<String> mergePinnedIdsPreservingOrder(List<List<String>> pinLists) {
  final mergedPins = <String>[];
  final seen = <String>{};

  for (final pinIds in pinLists) {
    for (final pinId in pinIds) {
      if (seen.add(pinId)) {
        mergedPins.add(pinId);
      }
    }
  }

  return mergedPins;
}

Future<List<String>> _loadManualPinsForTours({
  required Ref ref,
  required List<String> tourIds,
}) async {
  final storage = ref.read(forYouPinStorageProvider);
  final pinLists = await Future.wait(
    tourIds.map((tourId) => storage.getPinnedGameIds(tourId)),
  );
  return mergePinnedIdsPreservingOrder(pinLists);
}

Future<List<String>> _loadUnpinnedOverridesForTours({
  required Ref ref,
  required List<String> tourIds,
}) async {
  final storage = ref.read(forYouPinStorageProvider);
  final overrideLists = await Future.wait(
    tourIds.map((tourId) => storage.getUnpinnedGameIds(tourId)),
  );
  return mergePinListsPreservingOrder(overrideLists);
}

Future<List<String>> _loadAutoPins({
  required Ref ref,
  required String tourId,
  required List<GamesTourModel> allRelevantGames,
}) async {
  final prefsRepo = AutoPinPreferencesRepository(AppDatabase.instance);
  final userId = ref.read(currentUserProvider)?.id;
  final setupResults = await Future.wait<Object?>([
    prefsRepo.getTournamentAutoPinDisabled(tourId, userId),
    ref.read(autoPinPreferencesProvider.future),
  ]);
  final autoPinDisabled = setupResults[0]! as bool;
  if (autoPinDisabled) {
    return const <String>[];
  }

  final prefs = setupResults[1]! as AutoPinPreferences;
  if (!prefs.favoritePlayersAutoPinEnabled && !prefs.countrymenAutoPinEnabled) {
    return const <String>[];
  }

  final pinnedIds = <String>{};
  final dependencyResults = await Future.wait<Object?>([
    prefs.favoritePlayersAutoPinEnabled
        ? ref.read(tournamentFavoritePlayersProvider.future)
        : Future.value(null),
    prefs.countrymenAutoPinEnabled
        ? _resolveAutoPinCountryCode(ref)
        : Future.value(null),
  ]);
  final favoritePlayers =
      dependencyResults[0] as List<PlayerStandingModel>? ??
      const <PlayerStandingModel>[];
  final countryCode = dependencyResults[1] as String?;

  if (prefs.favoritePlayersAutoPinEnabled) {
    for (final game in allRelevantGames) {
      final matchesFavorite =
          favoritePlayers.any(
            (player) =>
                player.name == game.whitePlayer.name &&
                (player.countryCode.isEmpty ||
                    CountryCodeMatcher.matches(
                      game.whitePlayer.countryCode,
                      player.countryCode,
                    )),
          ) ||
          favoritePlayers.any(
            (player) =>
                player.name == game.blackPlayer.name &&
                (player.countryCode.isEmpty ||
                    CountryCodeMatcher.matches(
                      game.blackPlayer.countryCode,
                      player.countryCode,
                    )),
          );
      if (matchesFavorite) {
        pinnedIds.add(game.gameId);
      }
    }
  }

  if (prefs.countrymenAutoPinEnabled) {
    if (countryCode != null && countryCode.isNotEmpty) {
      final countryGames =
          allRelevantGames
              .where((game) {
                return CountryCodeMatcher.matches(
                      game.whitePlayer.countryCode,
                      countryCode,
                    ) ||
                    CountryCodeMatcher.matches(
                      game.blackPlayer.countryCode,
                      countryCode,
                    );
              })
              .map((game) => game.gameId)
              .toList();

      if (countryGames.length < allRelevantGames.length) {
        pinnedIds.addAll(countryGames);
      }
    }
  }

  return pinnedIds.toList();
}

@visibleForTesting
bool shouldLoadDeferredActivityTourId({
  required List<TourModel> tourModels,
  String? currentSelectedId,
  String? savedTourId,
}) {
  final hasStartedTours = tourModels.any(
    (model) => model.roundStatus != RoundStatus.upcoming,
  );

  bool canUseSelection(TourModel model) {
    if (!hasStartedTours) {
      return true;
    }
    return model.roundStatus != RoundStatus.upcoming;
  }

  Tour? findSelectableTour(String? tourId) {
    if (tourId == null || tourId.isEmpty) {
      return null;
    }

    for (final model in tourModels) {
      if (model.tour.id == tourId && canUseSelection(model)) {
        return model.tour;
      }
    }

    return null;
  }

  if (findSelectableTour(currentSelectedId) != null) {
    return false;
  }

  if (findSelectableTour(savedTourId) != null) {
    return false;
  }

  if (tourModels.any((model) => model.roundStatus == RoundStatus.live)) {
    return false;
  }

  final selectableModels =
      hasStartedTours
          ? tourModels
              .where((model) => model.roundStatus != RoundStatus.upcoming)
              .toList()
          : List<TourModel>.from(tourModels);

  if (selectableModels.isEmpty) {
    return true;
  }

  final toursWithDates =
      selectableModels.where((model) => model.tour.dates.isNotEmpty).toList();

  if (toursWithDates.isNotEmpty) {
    final firstStart = toursWithDates.first.tour.dates.first;
    final allSameStart = toursWithDates.every(
      (model) =>
          model.tour.dates.first.year == firstStart.year &&
          model.tour.dates.first.month == firstStart.month &&
          model.tour.dates.first.day == firstStart.day,
    );

    if (!allSameStart) {
      return false;
    }

    if (toursWithDates.any((model) => model.tour.avgElo != null)) {
      return false;
    }
  }

  if (selectableModels.any((model) => model.tour.avgElo != null)) {
    return false;
  }

  return true;
}

Future<String?> _resolveAutoPinCountryCode(Ref ref) async {
  final cachedCountryCode = await AppDatabase.instance.getString(
    'selected_country_code',
  );
  if (cachedCountryCode != null && cachedCountryCode.isNotEmpty) {
    return cachedCountryCode;
  }

  final countryAsync = ref.read(countryDropdownProvider);
  if (countryAsync.hasValue && countryAsync.value != null) {
    return countryAsync.value!.countryCode;
  }

  return countryAsync.valueOrNull?.countryCode;
}

// ============================================================================
// LIVE GAME WATCHER - AUTO-REFRESH WHEN GAMES FINISH
// ============================================================================

/// Watches displayed live games so each visible For You section stays reactive
/// to Supabase row updates, while still using [eventGamesProvider] for the
/// cached/refreshed snapshot.
///
/// The card widgets consume their own live row data, but this wrapper keeps the
/// section subscribed to the same rendered live rows and refreshes the snapshot
/// as soon as a displayed game finishes.
final forYouEventGamesWithAutoRefreshProvider = Provider.autoDispose.family<
  AsyncValue<ForYouEventGamesSnapshot>,
  String
>((ref, eventId) {
  final snapshotAsync = ref.watch(eventGamesProvider(eventId));

  return snapshotAsync.when(
    data: (snapshot) {
      final liveGames =
          snapshot.visibleGames
              .take(kGamesPerEvent)
              .where((game) => game.gameStatus == GameStatus.ongoing)
              .toList();

      for (final game in liveGames) {
        final updatesAsync = ref.watch(gameUpdatesStreamProvider(game.gameId));
        updatesAsync.whenData((data) {
          final status = data?['status'] as String?;
          if (status != null && _isFinishedStatus(status)) {
            debugPrint(
              '[ForYou] Game ${game.gameId} finished ($status), refreshing snapshot for event $eventId',
            );
            Future.microtask(() {
              bumpEventPinRefreshSignal(ref, eventId);
            });
          }
        });
      }

      return AsyncValue.data(snapshot);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

/// Read-only snapshot alias for non-rendering code paths.
final forYouEventSnapshotProvider = Provider.autoDispose
    .family<AsyncValue<ForYouEventGamesSnapshot>, String>(
      (ref, eventId) =>
          ref.watch(forYouEventGamesWithAutoRefreshProvider(eventId)),
    );

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
