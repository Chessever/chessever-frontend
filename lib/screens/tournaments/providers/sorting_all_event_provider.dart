import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tournamentSortingServiceProvider = Provider<TournamentSortingService>((
  ref,
) {
  return TournamentSortingService(ref);
});

class TournamentSortingService {
  final Ref ref;

  TournamentSortingService(this.ref);

  List<GroupEventCardModel> sortAllTours({
    required List<GroupEventCardModel> tours,
    required String dropDownSelectedCountry,
  }) {
    final filteredList =
        tours
            .where((t) => t.tourEventCategory != TourEventCategory.upcoming)
            .toList();

    filteredList.sort((a, b) {
      final isHighEloA = a.maxAvgElo > 3200;
      final isHighEloB = b.maxAvgElo > 3200;

      // If one has high ELO and the other doesn't, put high ELO at the end
      if (isHighEloA && !isHighEloB) return 1;
      if (!isHighEloA && isHighEloB) return -1;

      // If both are high ELO or both are normal ELO, sort by ELO descending
      final eloComparison = b.maxAvgElo.compareTo(a.maxAvgElo);
      if (eloComparison != 0) return eloComparison;

      // FINAL PRIORITY: Sort by title if everything else is equal
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filteredList;
  }

  List<GroupEventCardModel> sortUpcomingTours({
    required List<GroupEventCardModel> tours,
    required String dropDownSelectedCountry,
  }) {
    final filteredList =
        tours
            .where((t) => t.tourEventCategory == TourEventCategory.upcoming)
            .toList();

    filteredList.sort((a, b) {
      // For upcoming tournaments, also sort by maxElo after favorites
      // Special handling for tournaments with maxElo > 3200
      final eloA = a.maxAvgElo;
      final eloB = b.maxAvgElo;

      final isHighEloA = eloA > 3200;
      final isHighEloB = eloB > 3200;

      // If one has high ELO and the other doesn't, put high ELO at the end
      if (isHighEloA && !isHighEloB) return 1;
      if (!isHighEloA && isHighEloB) return -1;

      // If both are high ELO or both are normal ELO, sort by ELO descending
      final eloComparison = eloB.compareTo(eloA);
      if (eloComparison != 0) return eloComparison;

      // Finally sort by title
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filteredList;
  }

  List<GroupEventCardModel> sortBasedOnFavorite({
    required List<GroupEventCardModel> tours,
    required List<String> favorites,
  }) {
    final hasFavorites = favorites.isNotEmpty;

    var sortedEvents = tours.toList();
    sortedEvents.sort((a, b) {
      final isFavoriteA = favorites.contains(a.id);
      final isFavoriteB = favorites.contains(b.id);

      if (hasFavorites) {
        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return sortedEvents;
  }
}
