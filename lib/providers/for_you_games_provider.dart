import 'dart:async';

import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_status_stream_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int kGamesPerEvent = 4;
const int _kPageSize = 20;

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

  ForYouNotifier(this.ref) : super(const ForYouState(isLoading: true)) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await _fetchPage(isInitial: true);
  }

  Future<void> refresh() async {
    _offset = 0;
    state = const ForYouState(isLoading: true);
    await _fetchPage(isInitial: true);
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
      final formatFilters = appliedFilters.formatsAndStates
          .where((f) => ['blitz', 'rapid', 'standard'].contains(f.toLowerCase()))
          .map((f) => f.toLowerCase())
          .toList();

      final statusFilters = appliedFilters.formatsAndStates
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

      debugPrint('[ForYou] Fetched ${broadcasts.length} from Supabase (offset: $_offset, filters: format=$formatFilters, elo=$hasEloFilter)');

      // Get live IDs for status filtering
      final liveIds = ref.read(liveGroupBroadcastIdsProvider).valueOrNull ?? [];

      // Apply status filter (live/completed) - can't do in DB query
      List<GroupBroadcast> filteredBroadcasts = broadcasts;
      if (statusFilters.isNotEmpty) {
        filteredBroadcasts = broadcasts.where((tour) {
          final isLive = liveIds.contains(tour.id);
          return (statusFilters.contains('live') && isLive) ||
                 (statusFilters.contains('completed') && !isLive);
        }).toList();
      }

      // Convert to models
      final models = filteredBroadcasts
          .map((b) => GroupEventCardModel.fromGroupBroadcast(b, liveIds))
          .toList();

      // Pre-fetch heart data for this batch
      await _prefetchHeartData(models);

      // Sort this batch
      final sortedModels = await _sortModels(models);

      // Update state
      if (isInitial) {
        state = ForYouState(
          events: sortedModels,
          isLoading: false,
          hasMore: broadcasts.length >= _kPageSize,
        );
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
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _prefetchHeartData(List<GroupEventCardModel> models) async {
    final futures = models.map((event) async {
      try {
        final data = await ref.read(eventFavoritePlayersProvider(event.id).future);
        return MapEntry(event.id, data);
      } catch (e) {
        return MapEntry(event.id, const EventFavoritePlayers.empty());
      }
    }).toList();

    final results = await Future.wait(futures);
    final map = Map.fromEntries(results);
    ref.read(eventFavoritePlayersCacheProvider.notifier).updateCacheBatch(map);
  }

  Future<List<GroupEventCardModel>> _sortModels(List<GroupEventCardModel> models) async {
    final favoriteEventsAsync = ref.read(favoriteEventsProvider);
    final favoriteEvents = favoriteEventsAsync.valueOrNull ?? [];
    final starredIds = favoriteEvents.map((e) => e.eventId).toList();

    final favoriteTimestamps = <String, DateTime>{};
    for (final fav in favoriteEvents) {
      favoriteTimestamps[fav.eventId] = fav.createdAt;
    }

    final cache = ref.read(eventFavoritePlayersCacheProvider);

    return ref.read(tournamentSortingServiceProvider).sortBasedOnFavorite(
      tours: models,
      favorites: starredIds,
      eventFavoritePlayersMap: cache,
      favoriteTimestamps: favoriteTimestamps,
    );
  }
}

final forYouEventsProvider = StateNotifierProvider.autoDispose<ForYouNotifier, ForYouState>((ref) {
  ref.keepAlive();
  return ForYouNotifier(ref);
});

// ============================================================================
// LAZY GAMES PER EVENT PROVIDER
// ============================================================================

final eventGamesProvider = FutureProvider.autoDispose
    .family<List<Games>, String>((ref, eventId) async {
  ref.keepAlive();

  final repository = ref.read(gameRepositoryProvider);
  final groupBroadcastRepo = ref.read(groupBroadcastRepositoryProvider);

  final favoritesState = ref.read(favoritePlayersNotifierProvider).valueOrNull;
  final favoritePlayers = favoritesState?.players ?? [];
  final favoriteFideIds = favoritePlayers
      .where((p) => p.fideId != null && p.fideId! > 0)
      .map((p) => p.fideId!)
      .toSet();

  List<String> tourIds;
  try {
    tourIds = await groupBroadcastRepo.getTourIdsForGroupBroadcast(eventId);
    if (tourIds.isEmpty) tourIds = [eventId];
  } catch (e) {
    tourIds = [eventId];
  }

  final allGames = await repository.getGamesFromTourIds(
    tourIds: tourIds,
    limit: 50,
    offset: 0,
  );

  if (allGames.isEmpty) return [];

  final playedGames = allGames
      .where((g) => _hasStarted(g))
      .where((g) => g.players != null && g.players!.length >= 2)
      .toList();

  if (playedGames.isEmpty) return [];

  return _selectTopGames(playedGames, favoriteFideIds, kGamesPerEvent);
});

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

List<Games> _selectTopGames(List<Games> games, Set<int> favoriteFideIds, int count) {
  final liveGames = <Games>[];
  final favoriteGames = <Games>[];
  final regularGames = <Games>[];

  for (final game in games) {
    final isLive = game.status == '*' || game.status == 'ongoing';
    if (isLive) {
      liveGames.add(game);
    } else if (_hasFavoritePlayer(game, favoriteFideIds)) {
      favoriteGames.add(game);
    } else {
      regularGames.add(game);
    }
  }

  int compareByElo(Games a, Games b) => _getMaxElo(b).compareTo(_getMaxElo(a));
  liveGames.sort(compareByElo);
  favoriteGames.sort(compareByElo);
  regularGames.sort(compareByElo);

  final result = <Games>[];
  for (final game in [...liveGames, ...favoriteGames, ...regularGames]) {
    if (result.length >= count) break;
    result.add(game);
  }
  return result;
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
// LIVE GAME WATCHER - AUTO-REFRESH WHEN GAMES FINISH
// ============================================================================

/// Watches the status of displayed games and returns updated list
/// When a live game finishes, it automatically re-fetches to show next live game
final forYouEventGamesWithAutoRefreshProvider = Provider.autoDispose
    .family<AsyncValue<List<Games>>, String>((ref, eventId) {
  // Watch the base games provider
  final gamesAsync = ref.watch(eventGamesProvider(eventId));

  return gamesAsync.when(
    data: (games) {
      // Find live games in current selection
      final liveGames = games.where((g) =>
        g.status == '*' || g.status == 'ongoing'
      ).toList();

      // Watch status streams for all live games
      for (final game in liveGames) {
        final statusAsync = ref.watch(gameStatusStreamProvider(game.id));
        statusAsync.whenData((status) {
          // If status changed to finished, invalidate to re-fetch
          if (status != null && _isFinishedStatus(status)) {
            debugPrint('[ForYou] Game ${game.id} finished ($status), refreshing games for event $eventId');
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

final convertedForYouGamesProvider = Provider.autoDispose<List<GamesTourModel>>((ref) {
  return const [];
});

final forYouAnimatedGameIds = <String>{};
final forYouAnimatedEventIds = <String>{};
