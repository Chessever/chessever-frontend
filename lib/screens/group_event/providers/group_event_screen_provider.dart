import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/interfaces/igroup_event_screen_controller.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';

final selectedPlayerNameProvider = StateProvider<String?>((ref) => null);
final isSearchingProvider = StateProvider<bool>((ref) => false);
final searchQueryProvider = StateProvider<String>((ref) => '');
final liveBroadcastIdsProvider = StateProvider<List<String>>((ref) => []);

final supabaseSearchProvider =
    FutureProvider.family<List<GroupBroadcast>, String>((ref, query) async {
      return ref
          .read(groupBroadcastRepositoryProvider)
          .searchGroupBroadcastsFromSupabase(query);
    });

final groupEventScreenProvider = AutoDisposeStateNotifierProvider<
  _GroupEventScreenController,
  AsyncValue<List<GroupEventCardModel>>
>((ref) {
  final tourEventCategory = ref.watch(selectedGroupCategoryProvider);

  return _GroupEventScreenController(
    ref: ref,
    tourEventCategory: tourEventCategory,
  );
});

class _GroupEventScreenController
    extends StateNotifier<AsyncValue<List<GroupEventCardModel>>>
    implements IGroupEventScreenController {
  _GroupEventScreenController({
    required this.ref,
    required this.tourEventCategory,
  }) : super(const AsyncValue.loading()) {
    loadTours();
    _listenToLiveIds();
  }

  @override
  final Ref ref;
  @override
  final GroupEventCategory tourEventCategory;
  bool get isFetchingMore => _pastIsFetching;

  int _pastOffset = 50;
  final int _pastLimit = 50;
  bool _pastIsFetching = false;
  bool pastHasMore = true;

  var _groupBroadcastList = <GroupBroadcast>[];

  void _listenToLiveIds() {
    ref.listen<AsyncValue<List<String>>>(liveGroupBroadcastIdsProvider, (
      previous,
      next,
    ) {
      next.whenData((liveIds) {
        // Only update if live IDs actually changed
        if (ref.read(liveBroadcastIdsProvider).length != liveIds.length ||
            !ref
                .read(liveBroadcastIdsProvider)
                .every((id) => liveIds.contains(id))) {
          ref.read(liveBroadcastIdsProvider.notifier).state = liveIds;
          _updateLiveStatusInExistingModels();
        }
      });
    });
  }

  // Update live status without rebuilding the entire state
  void _updateLiveStatusInExistingModels() {
    final currentModels = state.valueOrNull;
    if (currentModels == null || currentModels.isEmpty) return;

    // Create updated models with new live status
    final updatedModels =
        currentModels.map((model) {
          return GroupEventCardModel.fromGroupBroadcast(
            _groupBroadcastList.firstWhere(
              (broadcast) => broadcast.id == model.id,
              orElse: () => _groupBroadcastList.first,
            ),
            ref.read(liveBroadcastIdsProvider),
          );
        }).toList();

    // Only update state if there are actual changes in live status
    bool hasChanges = false;
    for (int i = 0; i < currentModels.length; i++) {
      if (currentModels[i].tourEventCategory !=
          updatedModels[i].tourEventCategory) {
        hasChanges = true;
        break;
      }
    }

    if (hasChanges) {
      state = AsyncValue.data(updatedModels);
    }
  }

  @override
  Future<void> loadTours({
    List<GroupBroadcast>? inputBroadcast,
    List<String>? liveIds,
  }) async {
    try {
      state = const AsyncValue.loading();

      List<GroupBroadcast> tour = <GroupBroadcast>[];

      if (inputBroadcast != null) {
        tour = inputBroadcast;
      } else {
        tour =
            await ref
                .read(groupBroadcastLocalStorage(tourEventCategory))
                .fetchGroupBroadcasts();

        if (tourEventCategory == GroupEventCategory.past) {
          tour = await _ensureStarredEventsIncluded(tour);
        }
      }
      if (tour.isEmpty) {
        state = AsyncValue.data(<GroupEventCardModel>[]);
        return;
      }

      _groupBroadcastList = tour;

      final sortingService = ref.read(tournamentSortingServiceProvider);

      final tourEventCardModel =
          tour
              .map(
                (t) => GroupEventCardModel.fromGroupBroadcast(
                  t,
                  liveIds ?? ref.read(liveBroadcastIdsProvider),
                ),
              )
              .toList();

      final sortedTours =
          tourEventCategory == GroupEventCategory.upcoming
              ? sortingService.sortUpcomingTours(tourEventCardModel)
              : tourEventCategory == GroupEventCategory.past
              ? sortingService.sortPastTours(tourEventCardModel)
              : sortingService.sortAllTours(tourEventCardModel);

      state = AsyncValue.data(sortedTours);
    } catch (error, _) {}
  }

  Future<List<GroupBroadcast>> _ensureStarredEventsIncluded(
    List<GroupBroadcast> tours,
  ) async {
    // Get starred event IDs
    final starredIds = ref.read(starredProvider(tourEventCategory.name));

    final allStarredIds = <String>{...starredIds};

    if (allStarredIds.isEmpty) return tours;

    // Find starred events that might not be in current tour list
    final currentIds = tours.map((t) => t.id).toSet();
    final missingStarredIds = allStarredIds.where(
      (id) => !currentIds.contains(id),
    );

    if (missingStarredIds.isEmpty) return tours;

    // Fetch missing starred events
    final missingStarredEvents = <GroupBroadcast>[];
    for (final id in missingStarredIds) {
      try {
        final event = await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastById(id);
        missingStarredEvents.add(event);
      } catch (e) {
        continue;
      }
    }

    return [
      ...missingStarredEvents.where((e) => !currentIds.contains(e.id)),
      ...tours,
    ];
  }

  Future<void> loadMorePast() async {
    if (_pastIsFetching || !pastHasMore) return;
    _pastIsFetching = true;
    state = AsyncValue.data(state.valueOrNull ?? []);
    try {
      final repo = ref.read(groupBroadcastRepositoryProvider);
      final broadcasts = await repo.getPastGroupBroadcasts(
        limit: _pastLimit,
        offset: _pastOffset,
      );

      final existingIds = state.valueOrNull?.map((e) => e.id).toSet() ?? {};
      final newModels =
          broadcasts
              .where((b) => !existingIds.contains(b.id))
              .map(
                (b) => GroupEventCardModel.fromGroupBroadcast(
                  b,
                  ref.read(liveBroadcastIdsProvider),
                ),
              )
              .toList();

      final current = state.valueOrNull ?? [];
      final totalEvents = [...current, ...newModels];

      final sortedEvents = ref
          .read(tournamentSortingServiceProvider)
          .sortPastTours(totalEvents);

      state = AsyncValue.data(sortedEvents);

      _pastOffset += newModels.length;
      pastHasMore = broadcasts.length == _pastLimit;
    } catch (_) {
    } finally {
      _pastIsFetching = false;
    }
  }

  @override
  Future<void> setFilteredModels(List<GroupBroadcast> filterBroadcast) async {
    await loadTours(inputBroadcast: filterBroadcast);
  }

  @override
  Future<void> resetFilters() async {
    await loadTours();
  }

  @override
  Future<void> onRefresh() async {
    try {
      state = const AsyncValue.loading();

      final refreshed =
          await ref
              .read(groupBroadcastLocalStorage(tourEventCategory))
              .refresh();

      _groupBroadcastList = refreshed;
      final tourEventCardModel =
          refreshed
              .map(
                (t) => GroupEventCardModel.fromGroupBroadcast(
                  t,
                  ref.read(liveBroadcastIdsProvider),
                ),
              )
              .toList();
      final sortingService = ref.read(tournamentSortingServiceProvider);

      final sortedTours =
          tourEventCategory == GroupEventCategory.upcoming
              ? sortingService.sortUpcomingTours(tourEventCardModel)
              : tourEventCategory == GroupEventCategory.past
              ? sortingService.sortPastTours(tourEventCardModel)
              : sortingService.sortAllTours(tourEventCardModel);

      state = AsyncValue.data(sortedTours);
    } catch (err, stk) {
      state = AsyncValue.error(err, stk);
    }
  }

  @override
  void onSelectTournament({
    required BuildContext context,
    required String id,
  }) async {
    try {
      // First try to find in current list
      GroupBroadcast? selectedBroadcast;
      for (final broadcast in _groupBroadcastList) {
        if (broadcast.id == id) {
          selectedBroadcast = broadcast;
          break;
        }
      }

      // If not found in current list, fetch directly from repository
      selectedBroadcast ??= await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(id);

      ref.read(selectedBroadcastModelProvider.notifier).state =
          selectedBroadcast;

      if (context.mounted && ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (e, st) {
      state = AsyncValue.error('Tournament not found: $id', st);
    }
  }

  @override
  void onSelectPlayer({
    required BuildContext context,
    required SearchPlayer player,
  }) {
    final selectedBroadcast = _groupBroadcastList.firstWhere(
      (broadcast) => broadcast.id == player.tournamentId,
      orElse: () => _groupBroadcastList.first,
    );

    ref.read(selectedBroadcastModelProvider.notifier).state = selectedBroadcast;

    ref.read(selectedPlayerNameProvider.notifier).state = player.name;

    ref.invalidate(gamesAppBarProvider);
    ref.invalidate(gamesTourScreenProvider);
    ref.invalidate(playerTourScreenProvider);
    ref.invalidate(tourDetailScreenProvider);

    if (ref.read(selectedBroadcastModelProvider) != null) {
      Navigator.pushNamed(context, '/tournament_detail_screen');
    }
  }

  @override
  Future<void> searchForTournament(
    String query,
    GroupEventCategory tourEventCategory,
  ) async {
    if (query.isEmpty) {
      await loadTournaments(tourEventCategory);
      return;
    }

    state = const AsyncValue.loading();

    try {
      final broadcasts = await ref.read(supabaseSearchProvider(query).future);

      final tourEventCardModel =
          broadcasts
              .map(
                (b) => GroupEventCardModel.fromGroupBroadcast(
                  b,
                  ref.read(liveBroadcastIdsProvider),
                ),
              )
              .toList();

      state = AsyncValue.data(tourEventCardModel);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  @override
  Future<void> loadTournaments(GroupEventCategory tourEventCategory) async {
    state = const AsyncValue.loading();

    try {
      final groupBroadcast =
          await ref
              .read(groupBroadcastLocalStorage(tourEventCategory))
              .getGroupBroadcasts();

      final filteredTournaments =
          groupBroadcast
              .map(
                (e) => GroupEventCardModel.fromGroupBroadcast(
                  e,
                  ref.read(liveBroadcastIdsProvider),
                ),
              )
              .where((tour) {
                if (tourEventCategory == GroupEventCategory.current) {
                  return true;
                } else if (tourEventCategory == GroupEventCategory.upcoming) {
                  return tour.tourEventCategory == TourEventCategory.upcoming;
                } else {
                  return true;
                }
              })
              .toList();

      state = AsyncValue.data(filteredTournaments);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  @override
  Future<List<SearchPlayer>> getAllPlayersFromCurrentTournaments() async {
    try {
      final allPlayers = <SearchPlayer>[];
      for (final broadcast in _groupBroadcastList) {
        final players = await _fetchPlayersFromTournament(broadcast.id);
        allPlayers.addAll(players);
      }
      return allPlayers;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<SearchPlayer>> searchPlayersOnly(String query) async {
    if (query.isEmpty) return [];
    try {
      final allPlayers = await getAllPlayersFromCurrentTournaments();
      final queryLower = query.toLowerCase().trim();
      return allPlayers.where((player) {
          return player.name.toLowerCase().contains(queryLower);
        }).toList()
        ..sort((a, b) {
          final aExact = a.name.toLowerCase() == queryLower;
          final bExact = b.name.toLowerCase() == queryLower;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;
          final aStarts = a.name.toLowerCase().startsWith(queryLower);
          final bStarts = b.name.toLowerCase().startsWith(queryLower);
          if (aStarts && !bStarts) return -1;
          if (!aStarts && bStarts) return 1;
          return a.name.compareTo(b.name);
        });
    } catch (e) {
      return [];
    }
  }

  Future<List<SearchPlayer>> _fetchPlayersFromTournament(
    String tournamentId,
  ) async {
    try {
      final broadcast = _groupBroadcastList.firstWhere(
        (b) => b.id == tournamentId,
        orElse: () => throw Exception('Tournament not found'),
      );

      final players = <SearchPlayer>[];
      for (final searchTerm in broadcast.search) {
        if (_isPlayerName(searchTerm)) {
          players.add(
            SearchPlayer.fromSearchTerm(
              searchTerm,
              tournamentId,
              broadcast.name,
            ),
          );
        }
      }
      return players;
    } catch (e) {
      return [];
    }
  }

  bool _isPlayerName(String searchTerm) {
    final lowerTerm = searchTerm.toLowerCase();
    if (lowerTerm.contains('chess') ||
        lowerTerm.contains('tournament') ||
        lowerTerm.contains('championship') ||
        lowerTerm.contains('festival') ||
        lowerTerm.contains('open') ||
        lowerTerm.contains('classic')) {
      return false;
    }
    final words = searchTerm.trim().split(' ');
    if (words.length == 1 || (words.length >= 2 && words.length <= 4)) {
      return words.every(
        (w) => w.isNotEmpty && w[0] == w[0].toUpperCase() && w.length >= 1,
      );
    }
    return false;
  }
}
