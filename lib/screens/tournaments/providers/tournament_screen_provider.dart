import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum EventMode { live, completed, upcoming }

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
    _int();
  }

  final Ref ref;
  final TournamentCategory tourEventCategory;

  /// This will be populated every time we fetch the tournaments
  var _tours = <Tour>[];

  Future<void> _int() async {
    try {
      final tour = await ref.read(tourLocalStorageProvider).getTours();
      if (tour.isNotEmpty) {
        _tours = tour;
        final tourEventCardModel =
            tour.map((t) {
              return TourEventCardModel.fromTour(t);
            }).toList();
        final matchingTours =
            tourEventCardModel.where((e) {
              switch (tourEventCategory) {
                case TournamentCategory.all:
                  return true;
                case TournamentCategory.upcoming:
                  return e.tourEventCategory == TourEventCategory.upcoming;
              }
            }).toList();
        state = AsyncValue.data(matchingTours);
      }
    } catch (error, _) {
      print(error);
    }
  }

  Future<void> _calendarDetails(BuildContext context) async {
    try {
      final tour = await ref.read(tourLocalStorageProvider).getTours();

      if (tour.isNotEmpty) {
        _tours = tour;

        final tourEventCardModel =
            tour.map((t) {
              return TourEventCardModel.fromTour(t);
            }).toList();

        final args = ModalRoute.of(context)?.settings.arguments as Map?;
        final int? month = args?['month'];
        final int? year = args?['year'];

        final matchingTours =
            tourEventCardModel.where((e) {
              final eventDate = DateTime.tryParse(e.dates ?? '');
              if (eventDate == null) return false;

              final bool categoryMatch =
                  tourEventCategory == TournamentCategory.all ||
                  (tourEventCategory == TournamentCategory.upcoming &&
                      e.tourEventCategory == TourEventCategory.upcoming);

              final bool dateMatch =
                  (month == null || year == null)
                      ? true
                      : (eventDate.month == month && eventDate.year == year);

              return categoryMatch && dateMatch;
            }).toList();

        state = AsyncValue.data(matchingTours);
      }
    } catch (error, _) {
      print('Error loading tours: $error');
    }
  }

  Future<void> onRefresh() async {
    try {
      state = AsyncValue.loading();
      final tour = await ref.read(tourLocalStorageProvider).refresh();
      if (tour.isNotEmpty) {
        _tours = tour;
        final tourEventCardModel =
            tour.map((t) {
              return TourEventCardModel.fromTour(t);
            }).toList();
        final matchingTours =
            tourEventCardModel.where((e) {
              switch (tourEventCategory) {
                case TournamentCategory.all:
                  return true;
                case TournamentCategory.upcoming:
                  return e.tourEventCategory == TourEventCategory.upcoming;
              }
            }).toList();
        state = AsyncValue.data(matchingTours);
      }
    } catch (error, _) {
      print(error);
    }
  }

  void onSelectTournament({required BuildContext context, required String id}) {
    final tour = _tours.firstWhere(
      (tour) => tour.id == id,
      orElse: () => _tours.first,
    );
    if (tour.id.isNotEmpty) {
      ref.read(aboutTourModelProvider.notifier).state = AboutTourModel.fromTour(
        tour,
      );
    } else {
      ref.read(aboutTourModelProvider.notifier).state = AboutTourModel.fromTour(
        _tours.first,
      );
    }
    Navigator.pushNamed(context, '/tournament_detail_screen');
  }

  // Get filtered tournaments based on search query and tab selection
  Future<void> searchForTournament(
    String query,
    TournamentCategory tourEventCategory,
  ) async {
    if (query.isEmpty) {
      state = const AsyncValue.loading();
      _int();
      return;
    } else {
      final tours = await ref
          .read(tourLocalStorageProvider)
          .searchToursByName(query);
      final filteredTours =
          tours.where((tour) {
            final isMatchingName =
                tour.name.toLowerCase().contains(query.toLowerCase()) ||
                (tour.info.location?.toLowerCase().contains(
                      query.toLowerCase(),
                    ) ??
                    false);

            final tourCardModel = TourEventCardModel.fromTour(tour);

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
            tours.map((e) => TourEventCardModel.fromTour(e)).toList();
        state = AsyncValue.data(filteredTournaments);
      } else {
        final tours = await ref.read(tourRepositoryProvider).getRecentTours();
        final filteredTournaments =
            tours.map((e) => TourEventCardModel.fromTour(e)).toList();
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
      final tours = await ref.read(tourLocalStorageProvider).getTours();

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
