import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tournaments/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_screen.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../standings/standing_screen_provider.dart';

final tournamentNotifierProvider = AutoDisposeStateNotifierProvider<
  _TournamentScreenController,
  AsyncValue<List<TourEventCardModel>>
>((ref) {
  final tourEventCategory = ref.watch(selectedTourEventProvider);
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
  return _TournamentScreenController(
    ref: ref,
    tourEventCategory: tourEventCategory,
    liveBroadcastId: liveBroadcastId,
  );
});

class _TournamentScreenController
    extends StateNotifier<AsyncValue<List<TourEventCardModel>>> {
  _TournamentScreenController({
    required this.ref,
    required this.tourEventCategory,
    required this.liveBroadcastId,
  }) : super(const AsyncValue.loading()) {
    loadTours();
  }

  final Ref ref;
  final TournamentCategory tourEventCategory;
  final List<String> liveBroadcastId;

  /// This will be populated every time we fetch the tournaments
  var _groupBroadcastList = <GroupBroadcast>[];

  Future<void> loadTours({
    List<GroupBroadcast>? inputBroadcast,
    bool sortByFavorites = false,
  }) async {
    try {
      final tour =
          (inputBroadcast ??
              await ref
                  .read(groupBroadcastLocalStorage(tourEventCategory))
                  .fetchGroupBroadcasts());
      if (tour.isEmpty) {
        state = AsyncValue.data(<TourEventCardModel>[]);
      }

      _groupBroadcastList = tour;

      final countryAsync = ref.watch(countryDropdownProvider);
      if (countryAsync is AsyncData<Country>) {
        final selectedCountry = countryAsync.value.name.toLowerCase();
        final sortingService = ref.read(tournamentSortingServiceProvider);

        final tourEventCardModel =
            tour
                .map(
                  (t) =>
                      TourEventCardModel.fromGroupBroadcast(t, liveBroadcastId),
                )
                .toList();

        final sortedTours =
            tourEventCategory == TournamentCategory.upcoming
                ? sortingService.sortUpcomingTours(
                  tourEventCardModel,
                  selectedCountry,
                )
                : sortingService.sortAllTours(
                  tourEventCardModel,
                  selectedCountry,
                  sortByFavorites: sortByFavorites,
                );

        state = AsyncValue.data(sortedTours);
      }
    } catch (error, _) {
      print(error);
    }
  }

  Future<void> setFilteredModels(List<GroupBroadcast> filterBroadcast) async {
    await loadTours(inputBroadcast: filterBroadcast);
  }

  Future<void> resetFilters() async {
    await loadTours();
  }

  Future<void> onRefresh() async {
    try {
      state = AsyncValue.loading();
      final tour =
          await ref
              .read(groupBroadcastLocalStorage(tourEventCategory))
              .refresh();
      if (tour.isNotEmpty) {
        _groupBroadcastList = tour;
        final tourEventCardModel =
            tour.map((t) {
              return TourEventCardModel.fromGroupBroadcast(t, liveBroadcastId);
            }).toList();

        final countryAsync = ref.watch(countryDropdownProvider);

        // Check if country data is loaded
        if (countryAsync is AsyncData<Country>) {
          final selectedCountry = countryAsync.value.name.toLowerCase();

          final sortingService = ref.read(tournamentSortingServiceProvider);
          if (tourEventCategory == TournamentCategory.upcoming) {
            final sortedTours = sortingService.sortUpcomingTours(
              tourEventCardModel,
              selectedCountry,
            );
            state = AsyncValue.data(sortedTours);
          } else {
            final sortedTours = sortingService.sortAllTours(
              tourEventCardModel,
              selectedCountry,
            );

            state = AsyncValue.data(sortedTours);
          }
        } else {
          state = AsyncValue.loading();
        }
      }
    } catch (error, _) {
      print(error);
    }
  }

  //todo:
  // void onSelectTournament({required BuildContext context, required String id}) {
  //   final selectedBroadcast = _groupBroadcastList.firstWhere(
  //     (broadcast) => broadcast.id == id,
  //     orElse: () => _groupBroadcastList.first,
  //   );
  //   if (selectedBroadcast.id.isNotEmpty) {
  //     ref.read(selectedBroadcastModelProvider.notifier).state =
  //         selectedBroadcast;
  //   } else {
  //     ref.read(selectedBroadcastModelProvider.notifier).state =
  //         selectedBroadcast;
  //   }
  //   Navigator.pushNamed(context, '/tournament_detail_screen');
  // }

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

  // Get filtered tournaments based on search query and tab selection
  // Future<void> searchForTournament(
  //   String query,
  //   TournamentCategory tourEventCategory,
  // ) async {
  //   state = const AsyncValue.loading();

  //   try {
  //     final groupBroadcast = await ref
  //         .read(groupBroadcastLocalStorage(tourEventCategory))
  //         .searchGroupBroadcastsByName(query);

  //     final filteredTours =
  //         groupBroadcast.where((tour) {
  //           final tourCardModel = TourEventCardModel.fromGroupBroadcast(
  //             tour,
  //             liveBroadcastId,
  //           );

  //           // Filter by category
  //           if (tourEventCategory == TournamentCategory.current) {
  //             return true;
  //           } else if (tourEventCategory == TournamentCategory.upcoming) {
  //             return tourCardModel.tourEventCategory ==
  //                 TourEventCategory.upcoming;
  //           } else {
  //             // Add other category checks here if needed
  //             return true;
  //           }
  //         }).toList();

  //     final filteredTournaments =
  //         filteredTours
  //             .map(
  //               (e) =>
  //                   TourEventCardModel.fromGroupBroadcast(e, liveBroadcastId),
  //             )
  //             .toList();

  //     state = AsyncValue.data(filteredTournaments);
  //   } catch (error, stackTrace) {
  //     state = AsyncValue.error(error, stackTrace);
  //   }
  // }

  Future<void> searchForTournament(
    String query,
    TournamentCategory tourEventCategory,
  ) async {
    if (query.isEmpty) {
      // Load all tournaments when query is empty
      await loadTournaments(tourEventCategory);
      return;
    }

    state = const AsyncValue.loading();

    try {
      final searchResult = await ref
          .read(groupBroadcastLocalStorage(tourEventCategory))
          .searchWithScoring(query);

      // Combine both tournament and player results, prioritizing tournament matches
      final allResults = [
        ...searchResult.tournamentResults,
        ...searchResult.playerResults,
      ];

      // Remove duplicates while preserving the highest score for each tournament
      final Map<String, SearchResult> uniqueResults = {};
      for (final result in allResults) {
        final key = result.tournament.id;
        if (!uniqueResults.containsKey(key) ||
            result.score > uniqueResults[key]!.score) {
          uniqueResults[key] = result;
        }
      }

      // Apply category filter
      final filteredResults =
          uniqueResults.values.where((result) {
            if (tourEventCategory == TournamentCategory.current) {
              return true;
            } else if (tourEventCategory == TournamentCategory.upcoming) {
              return result.tournament.tourEventCategory ==
                  TourEventCategory.upcoming;
            } else {
              return true;
            }
          }).toList();

      // Sort by score and extract tournaments
      filteredResults.sort((a, b) => b.score.compareTo(a.score));
      final tournaments = filteredResults.map((r) => r.tournament).toList();

      state = AsyncValue.data(tournaments);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> loadTournaments(TournamentCategory tourEventCategory) async {
    // Original logic to load all tournaments
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
                    TourEventCardModel.fromGroupBroadcast(e, liveBroadcastId),
              )
              .where((tour) {
                if (tourEventCategory == TournamentCategory.current) {
                  return true;
                } else if (tourEventCategory == TournamentCategory.upcoming) {
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
}
