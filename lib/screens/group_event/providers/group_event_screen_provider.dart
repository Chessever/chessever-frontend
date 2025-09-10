import 'package:chessever2/providers/country_dropdown_provider.dart';
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
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../repository/supabase/group_broadcast/group_tour_repository.dart';
import '../../tour_detail/player_tour/player_tour_screen_provider.dart';

final _currentLiveIdsProvider = StateProvider<List<String>>((_) => const []);

final liveIdsProvider = Provider<List<String>>(
  (ref) => ref.watch(_currentLiveIdsProvider),
);

final selectedPlayerNameProvider = StateProvider<String?>((ref) => null);
final isSearchingProvider = StateProvider<bool>((ref) => false);
final searchQueryProvider = StateProvider<String>((ref) => '');

final supabaseSearchProvider =
    FutureProvider.family<List<GroupBroadcast>, String>(
      (ref, query) async {
        return ref
            .read(groupBroadcastRepositoryProvider)
            .searchGroupBroadcastsFromSupabase(query);
      },
    );

final groupEventScreenProvider = AutoDisposeStateNotifierProvider<
  _GroupEventScreenController,
  AsyncValue<List<GroupEventCardModel>>
>((ref) {
  final tourEventCategory = ref.watch(selectedGroupCategoryProvider);

  //  silent listener instead of watch
  ref.listen<AsyncValue<List<String>>>(
    liveGroupBroadcastIdsProvider,
    (previous, next) {
      next.whenData((liveIds) {
        ref.read(_currentLiveIdsProvider.notifier).state = liveIds;
      });
    },
  );

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
  }

  @override
  List<String> get liveBroadcastId => _liveBroadcastId;
  @override
  final Ref ref;
  @override
  final GroupEventCategory tourEventCategory;

  var _groupBroadcastList = <GroupBroadcast>[];

  // getter – no rebuilds
  List<String> get _liveBroadcastId => ref.read(_currentLiveIdsProvider);

  @override
  Future<void> loadTours({List<GroupBroadcast>? inputBroadcast}) async {
    try {
      final tour =
          inputBroadcast ??
          await ref
              .read(groupBroadcastLocalStorage(tourEventCategory))
              .fetchGroupBroadcasts();
      if (tour.isEmpty) {
        state = AsyncValue.data(<GroupEventCardModel>[]);
      }

      _groupBroadcastList = tour;

      final countryAsync = ref.watch(countryDropdownProvider);
      if (countryAsync is AsyncData<Country>) {
        final selectedCountry = countryAsync.value.name.toLowerCase();
        final sortingService = ref.read(tournamentSortingServiceProvider);

        final tourEventCardModel =
            tour
                .map(
                  (t) => GroupEventCardModel.fromGroupBroadcast(
                    t,
                    _liveBroadcastId,
                  ),
                )
                .toList();

        final sortedTours =
            tourEventCategory == GroupEventCategory.upcoming
                ? sortingService.sortUpcomingTours(
                  tours: tourEventCardModel,
                  dropDownSelectedCountry: selectedCountry,
                )
                : sortingService.sortAllTours(
                  tours: tourEventCardModel,
                  dropDownSelectedCountry: selectedCountry,
                );

        state = AsyncValue.data(sortedTours);
      }
    } catch (error, _) {
      print(error);
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

      final tour =
          await ref
              .read(groupBroadcastLocalStorage(tourEventCategory))
              .refresh();

      if (tour.isEmpty) {
        state = AsyncValue.data(<GroupEventCardModel>[]);
        return;
      }

      _groupBroadcastList = tour;

      final tourEventCardModel =
          tour
              .map(
                (t) => GroupEventCardModel.fromGroupBroadcast(
                  t,
                  _liveBroadcastId, //uses getter
                ),
              )
              .toList();

      final countryAsync = ref.watch(countryDropdownProvider);

      if (countryAsync is AsyncData<Country>) {
        final selectedCountry = countryAsync.value.name.toLowerCase();
        final sortingService = ref.read(tournamentSortingServiceProvider);

        final sortedTours =
            tourEventCategory == GroupEventCategory.upcoming
                ? sortingService.sortUpcomingTours(
                  tours: tourEventCardModel,
                  dropDownSelectedCountry: selectedCountry,
                )
                : sortingService.sortAllTours(
                  tours: tourEventCardModel,
                  dropDownSelectedCountry: selectedCountry,
                );

        state = AsyncValue.data(sortedTours);
      } else {
        state = const AsyncValue.loading();
      }
    } catch (error, _) {
      print(error);
    }
  }

  @override
  void onSelectTournament({required BuildContext context, required String id}) {
    final selectedBroadcast = _groupBroadcastList.firstWhere(
      (broadcast) => broadcast.id == id,
      orElse: () => _groupBroadcastList.first,
    );

    ref.read(selectedBroadcastModelProvider.notifier).state = selectedBroadcast;

    ref.invalidate(gamesAppBarProvider);
    ref.invalidate(gamesTourScreenProvider);
    ref.invalidate(playerTourScreenProvider);
    ref.invalidate(tourDetailScreenProvider);

    if (ref.read(selectedBroadcastModelProvider) != null) {
      Navigator.pushNamed(context, '/tournament_detail_screen');
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
                (b) =>
                    GroupEventCardModel.fromGroupBroadcast(b, liveBroadcastId),
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
                  _liveBroadcastId,
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
    if (words.length >= 2 && words.length <= 4) {
      return words.every(
        (word) =>
            word.isNotEmpty &&
            word[0] == word[0].toUpperCase() &&
            word.length > 1,
      );
    }
    return false;
  }
}
