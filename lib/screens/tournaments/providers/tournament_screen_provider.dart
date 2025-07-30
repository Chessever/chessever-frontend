import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
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
      final tour = await ref.read(groupBroadcastLocalStorage(tourEventCategory)).refresh();
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
    final tour = _groupBroadcastList.firstWhere(
      (tour) => tour.id == id,
      orElse: () => _groupBroadcastList.first,
    );
    // if (tour.id.isNotEmpty) {
    //   ref.read(aboutTourModelProvider.notifier).state = AboutTourModel.fromTour(
    //     tour,
    //   );
    // } else {
    //   ref.read(aboutTourModelProvider.notifier).state = AboutTourModel.fromTour(
    //     _groupBroadcastList.first,
    //   );
    // }
    Navigator.pushNamed(context, '/tournament_detail_screen');
  }

  // Get filtered tournaments based on search query and tab selection
  Future<void> searchForTournament(
    String query,
    TournamentCategory tourEventCategory,
  ) async {
    if (query.isEmpty) {
      state = const AsyncValue.loading();
      loadTours();
      return;
    } else {
      final groupBroadcast = await ref
          .read(groupBroadcastLocalStorage(tourEventCategory))
          .searchGroupBroadcastsByName(query);
      final filteredTours =
      groupBroadcast.where((tour) {
            final isMatchingName =
                tour.name.toLowerCase().contains(query.toLowerCase()) ||
                (tour.timeControl?.toLowerCase().contains(
                      query.toLowerCase(),
                    ) ??
                    false);

            final tourCardModel = TourEventCardModel.fromGroupBroadcast(tour);

            final isMatchingCategory =
                tourEventCategory == TournamentCategory.all
                    ? true
                    : tourEventCategory == TournamentCategory.upcoming
                    ? tourCardModel.tourEventCategory ==
                        TourEventCategory.upcoming
                    : true;

            return isMatchingName && isMatchingCategory;
          }).toList();

      if (filteredTours.isNotEmpty) {
        final filteredTournaments =
        groupBroadcast.map((e) => TourEventCardModel.fromGroupBroadcast(e)).toList();
        state = AsyncValue.data(filteredTournaments);
      } else {
        final tours = await ref.read(groupBroadcastLocalStorage(tourEventCategory)).getGroupBroadcasts();
        final filteredTournaments =
            tours.map((e) => TourEventCardModel.fromGroupBroadcast(e)).toList();
        state = AsyncValue.data(filteredTournaments);
      }
    }
  }
}

final calendarTourViewProvider = AutoDisposeStateNotifierProvider.family((
  ref,
  CalendarFilterArgs args,
) {
  return _CalendarTourViewController(
    ref: ref,
    month: args.month,
    year: args.year,
  );
});

class _CalendarTourViewController
    extends StateNotifier<AsyncValue<List<TourEventCardModel>>> {
  _CalendarTourViewController({
    required this.ref,
    required this.month,
    required this.year,
  }) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final int? month;
  final int? year;

  Future<void> _init() async {
    try {
      final tours = await ref.read(groupBroadcastLocalStorage()).getTours();

      if (tours.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      final selectedMonth = ref.read(selectedMonthProvider);
      final selectedYear = ref.read(selectedYearProvider);

      final filteredTours =
          tours.where((tour) {
            if (tour.dates.isEmpty) return false;

            final startDate = tour.dates.first;
            final endDate = tour.dates.last;

            // Create date range for selected month
            final monthStart = DateTime(selectedYear, selectedMonth, 1);
            final monthEnd = DateTime(selectedYear, selectedMonth + 1, 0);

            // Check if tournament date range overlaps with selected month
            return startDate.isBefore(monthEnd.add(Duration(days: 1))) &&
                endDate.isAfter(monthStart.subtract(Duration(days: 1)));
          }).toList();

      final filteredTourEventCards =
          filteredTours.map((t) => TourEventCardModel.fromTour(t)).toList();

      state = AsyncValue.data(filteredTourEventCards);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> search(String query) async {
    try {
      final tours = await ref.read(tourLocalStorageProvider).getTours();

      if (query.isEmpty) {
        _init(); // fallback to filtered list if query is empty
        return;
      }

      final filteredTours =
          tours.where((tour) {
            final matchesText =
                tour.name.toLowerCase().contains(query.toLowerCase()) ||
                (tour.info.location?.toLowerCase().contains(
                      query.toLowerCase(),
                    ) ??
                    false);

            final matchesDate = tour.dates.any((dateString) {
              final date = DateTime.tryParse(dateString.toString());
              if (date == null) return false;
              if (month == null || year == null) return true;
              return date.month == month && date.year == year;
            });

            return matchesText && matchesDate;
          }).toList();

      final filteredTourEventCards =
          filteredTours.map((t) => TourEventCardModel.fromTour(t)).toList();

      state = AsyncValue.data(filteredTourEventCards);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

class CalendarFilterArgs {
  final int? month;
  final int? year;

  const CalendarFilterArgs({this.month, this.year});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarFilterArgs &&
          runtimeType == other.runtimeType &&
          month == other.month &&
          year == other.year;

  @override
  int get hashCode => month.hashCode ^ year.hashCode;
}
