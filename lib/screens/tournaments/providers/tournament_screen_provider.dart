import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:easy_debounce/easy_debounce.dart';
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
      final tour = await ref.read(tourRepositoryProvider).getTours(limit: 10);
      if (tour.isNotEmpty) {
        _tours = tour;
        final tourEventCardModel =
            tour.map((t) {
              print(t.toJson());
              return TourEventCardModel.fromTour(t);
            }).toList();
        state = AsyncValue.data(tourEventCardModel);
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
