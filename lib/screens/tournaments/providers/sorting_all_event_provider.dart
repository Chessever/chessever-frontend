import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tournamentSortingServiceProvider = Provider<TournamentSortingService>((
  ref,
) {
  return TournamentSortingService(ref);
});

class TournamentSortingService {
  final Ref ref;

  TournamentSortingService(this.ref);

  List<TourEventCardModel> sortAllTours(
    List<TourEventCardModel> tours,
    String dropDownSelectedCountry, {
    bool sortByFavorites = false, // Add this optional flag
  }) {
    final favorites = ref.watch(starredProvider);
    final hasFavorites = favorites.isNotEmpty;

    final filteredList =
        tours
            .where((t) => t.tourEventCategory != TourEventCategory.upcoming)
            .toList();

    filteredList.sort((a, b) {
      if (sortByFavorites && hasFavorites) {
        final isFavoriteA = favorites.contains(a.id);
        final isFavoriteB = favorites.contains(b.id);

        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

      final statusPriorityA = _getTournamentStatusPriority(a.tourEventCategory);
      final statusPriorityB = _getTournamentStatusPriority(b.tourEventCategory);

      final statusComparison = statusPriorityA.compareTo(statusPriorityB);
      if (statusComparison != 0) return statusComparison;

      // Within the same status category, sort by maxElo (descending)
      if (a.tourEventCategory == TourEventCategory.live ||
          a.tourEventCategory == TourEventCategory.completed) {
        // Special handling for tournaments with maxElo > 3200
        final isHighEloA = a.maxAvgElo > 3200;
        final isHighEloB = b.maxAvgElo > 3200;

        // If one has high ELO and the other doesn't, put high ELO at the end
        if (isHighEloA && !isHighEloB) return 1;
        if (!isHighEloA && isHighEloB) return -1;

        // If both are high ELO or both are normal ELO, sort by ELO descending
        final eloComparison = b.maxAvgElo.compareTo(a.maxAvgElo);
        if (eloComparison != 0) return eloComparison;
      }

      // Finally sort by title if everything else is equal
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filteredList;
  }

  List<TourEventCardModel> sortUpcomingTours(
    List<TourEventCardModel> tours,
    String dropDownSelectedCountry,
  ) {
    final favorites = ref.watch(
      starredProvider,
    ); // Get the list of favorited ids
    final hasFavorites = favorites.isNotEmpty;

    final filteredList =
        tours
            .where((t) => t.tourEventCategory == TourEventCategory.upcoming)
            .toList();

    filteredList.sort((a, b) {
      final isFavoriteA = favorites.contains(a.id);
      final isFavoriteB = favorites.contains(b.id);

      if (hasFavorites) {
        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

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

  int _getTournamentStatusPriority(TourEventCategory category) {
    switch (category) {
      case TourEventCategory.live:
        return 1;
      case TourEventCategory.completed:
        return 2;
      default:
        return 3;
    }
  }
}
