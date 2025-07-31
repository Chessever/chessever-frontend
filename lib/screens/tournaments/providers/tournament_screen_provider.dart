import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tournamentNotifierProvider = AutoDisposeStateNotifierProvider<
  _TournamentScreenController,
  AsyncValue<List<TourEventCardModel>>
>((ref) {
  final tourEventCategory = ref.watch(selectedTourEventProvider);
  return _TournamentScreenController(
    ref: ref,
    tourEventCategory: tourEventCategory,
  );
});

class _TournamentScreenController
    extends StateNotifier<AsyncValue<List<TourEventCardModel>>> {
  _TournamentScreenController({
    required this.ref,
    required this.tourEventCategory,
  }) : super(const AsyncValue.loading()) {
    loadTours();
  }

  final Ref ref;
  final TournamentCategory tourEventCategory;

  /// This will be populated every time we fetch the tournaments
  var _groupBroadcastList = <GroupBroadcast>[];

  Future<void> loadTours({
    List<GroupBroadcast>? inputBroadcast,
    bool sortByFavorites = false,
  }) async {
    try {
      final tour =
          inputBroadcast ??
          await ref
              .read(groupBroadcastLocalStorage(tourEventCategory))
              .getGroupBroadcasts();
      if (tour.isEmpty) return;

      _groupBroadcastList = tour;

      final countryAsync = ref.watch(countryDropdownProvider);
      if (countryAsync is AsyncData<Country>) {
        final selectedCountry = countryAsync.value.name.toLowerCase();
        final sortingService = ref.read(tournamentSortingServiceProvider);

        final tourEventCardModel =
            tour.map((t) => TourEventCardModel.fromGroupBroadcast(t)).toList();

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
              return TourEventCardModel.fromGroupBroadcast(t);
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
  void onSelectTournament({required BuildContext context, required String id}) {
    final selectedBroadcast = _groupBroadcastList.firstWhere(
      (broadcast) => broadcast.id == id,
      orElse: () => _groupBroadcastList.first,
    );
    if (selectedBroadcast.id.isNotEmpty) {
      ref.read(selectedBroadcastModelProvider.notifier).state =
          selectedBroadcast;
    } else {
      ref.read(selectedBroadcastModelProvider.notifier).state =
          selectedBroadcast;
    }
    Navigator.pushNamed(context, '/tournament_detail_screen');
  }

  // Get filtered tournaments based on search query and tab selection
  Future<void> searchForTournament(
    String query,
    TournamentCategory tourEventCategory,
  ) async {
    state = const AsyncValue.loading();

    try {
      final groupBroadcast = await ref
          .read(groupBroadcastLocalStorage(tourEventCategory))
          .searchGroupBroadcastsByName(query);

      final filteredTours =
          groupBroadcast.where((tour) {
            final tourCardModel = TourEventCardModel.fromGroupBroadcast(tour);

            // Filter by category
            if (tourEventCategory == TournamentCategory.current) {
              return true;
            } else if (tourEventCategory == TournamentCategory.upcoming) {
              return tourCardModel.tourEventCategory ==
                  TourEventCategory.upcoming;
            } else {
              // Add other category checks here if needed
              return true;
            }
          }).toList();

      final filteredTournaments =
          filteredTours
              .map((e) => TourEventCardModel.fromGroupBroadcast(e))
              .toList();

      state = AsyncValue.data(filteredTournaments);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
