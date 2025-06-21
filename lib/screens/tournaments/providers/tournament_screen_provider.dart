import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tournaments/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:easy_debounce/easy_debounce.dart';
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

  Future<void> _int() async {
    try {
      final tour = await ref.read(tourRepositoryProvider).getTours(limit: 10);
      if (tour.isNotEmpty) {
        final tourEventCardModel =
            tour.map((t) {
              return TourEventCardModel.fromTour(t);
            }).toList();
        state = AsyncValue.data(tourEventCardModel);
      }
    } catch (error, _) {
      print(error);
    }
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
      EasyDebounce.debounce(
        'search_for_${tourEventCategory.name}',

        Duration(milliseconds: 600), // <-- The debounce duration
        () async {
          final tours = await ref
              .read(tourRepositoryProvider)
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
            final tours =
                await ref.read(tourRepositoryProvider).getRecentTours();
            final filteredTournaments =
                tours.map((e) => TourEventCardModel.fromTour(e)).toList();
            state = AsyncValue.data(filteredTournaments);
          }
        },
      );
    }
  }
}
