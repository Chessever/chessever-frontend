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

  List<GroupEventCardModel> sortAllTours(
    List<GroupEventCardModel> tours,
    String dropDownSelectedCountry, {
    bool sortByFavorites = false, // Add this optional flag
  }) {
    final favorites = ref.watch(starredProvider);
    final hasFavorites = favorites.isNotEmpty;

    final filteredList =
        tours
            .where((t) => t.tourEventCategory != TourEventCategory.upcoming)
            .toList()
            .where((t) {
              if (t.tourEventCategory == TourEventCategory.live) {
                return t.endDate?.isBefore(
                      DateTime.now().add(const Duration(days: 2)),
                    ) ??
                    false;
              }
              return true;
            })
            .toList();

    filteredList.sort((a, b) {
      // SECOND PRIORITY: General favorites (if sortByFavorites is enabled)
      if (sortByFavorites && hasFavorites) {
        final isFavoriteA = favorites.contains(a.id);
        final isFavoriteB = favorites.contains(b.id);

        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

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

  List<GroupEventCardModel> sortUpcomingTours(
    List<GroupEventCardModel> tours,
    String dropDownSelectedCountry,
  ) {
    final favorites = ref.watch(
      starredProvider,
    ); // Get the list of favorited ids
    final hasFavorites = favorites.isNotEmpty;

    final filteredList =
        tours
            .where((t) => t.tourEventCategory == TourEventCategory.upcoming)
            .toList()
            .where((p) => p.maxAvgElo > 0)
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
}
