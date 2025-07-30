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
