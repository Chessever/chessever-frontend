import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/interfaces/igroup_event_screen_controller.dart';
import 'package:chessever2/screens/tournaments/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tournaments/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_screen.dart';
import 'package:chessever2/screens/tournaments/group_event_screen.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../standings/standing_screen_provider.dart';

// New provider for selected player name
final selectedPlayerNameProvider = StateProvider<String?>((ref) => null);

final groupEventScreenProvider = AutoDisposeStateNotifierProvider<
  _GroupEventScreenController,
  AsyncValue<List<GroupEventCardModel>>
>((ref) {
  final tourEventCategory = ref.watch(selectedGroupCategoryProvider);

  var liveBroadcastId = <String>[];
  ref
      .watch(liveGroupBroadcastIdsProvider)
      .when(
        data: (liveIds) {
          liveBroadcastId = liveIds;
        },
        error: (error, _) {},
        loading: () {},
      );
  return _GroupEventScreenController(
    ref: ref,
    tourEventCategory: tourEventCategory,
    liveBroadcastId: liveBroadcastId,
  );
});

class _GroupEventScreenController
    extends StateNotifier<AsyncValue<List<GroupEventCardModel>>>
    implements IGroupEventScreenController {
  _GroupEventScreenController({
    required this.ref,
    required this.tourEventCategory,
    required this.liveBroadcastId,
  }) : super(const AsyncValue.loading()) {
    loadTours();
  }

  @override
  final Ref ref;
  @override
  final GroupEventCategory tourEventCategory;
  @override
  final List<String> liveBroadcastId;

  /// This will be populated every time we fetch the tournaments
  var _groupBroadcastList = <GroupBroadcast>[];

  @override
  Future<void> loadTours({List<GroupBroadcast>? inputBroadcast}) async {
    try {
      final tour =
          (inputBroadcast ??
              await ref
                  .read(groupBroadcastLocalStorage(tourEventCategory))
                  .fetchGroupBroadcasts());
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
                    liveBroadcastId,
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
                (t) =>
                    GroupEventCardModel.fromGroupBroadcast(t, liveBroadcastId),
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

    ref.read(selectedTourIdProvider.notifier).state = selectedBroadcast.id;
    ref.read(selectedBroadcastModelProvider.notifier).state = selectedBroadcast;

    ref.invalidate(gamesAppBarProvider);
    ref.invalidate(gamesTourScreenProvider);
    ref.invalidate(standingScreenProvider);
    ref.invalidate(tourDetailScreenProvider);

    Navigator.pushNamed(context, '/tournament_detail_screen');
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

    ref.read(selectedTourIdProvider.notifier).state = selectedBroadcast.id;
    ref.read(selectedBroadcastModelProvider.notifier).state = selectedBroadcast;

    // Store the selected player's name for use in GamesTourScreen
    ref.read(selectedPlayerNameProvider.notifier).state = player.name;

    ref.invalidate(gamesAppBarProvider);
    ref.invalidate(gamesTourScreenProvider);
    ref.invalidate(standingScreenProvider);
    ref.invalidate(tourDetailScreenProvider);

    Navigator.pushNamed(context, '/tournament_detail_screen');
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
      final searchResult = await ref
          .read(groupBroadcastLocalStorage(tourEventCategory))
          .searchWithScoring(query);

      final allResults = [
        ...searchResult.tournamentResults,
        ...searchResult.playerResults,
      ];

      final Map<String, SearchResult> uniqueResults = {};
      for (final result in allResults) {
        final key = result.tournament.id;
        if (!uniqueResults.containsKey(key) ||
            result.score > uniqueResults[key]!.score) {
          uniqueResults[key] = result;
        }
      }

      final filteredResults =
          uniqueResults.values.where((result) {
            if (tourEventCategory == GroupEventCategory.current) {
              return true;
            } else if (tourEventCategory == GroupEventCategory.upcoming) {
              return result.tournament.tourEventCategory ==
                  TourEventCategory.upcoming;
            } else {
              return true;
            }
          }).toList();

      filteredResults.sort((a, b) => b.score.compareTo(a.score));
      final tournaments = filteredResults.map((r) => r.tournament).toList();

      state = AsyncValue.data(tournaments);
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
                (e) =>
                    GroupEventCardModel.fromGroupBroadcast(e, liveBroadcastId),
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
