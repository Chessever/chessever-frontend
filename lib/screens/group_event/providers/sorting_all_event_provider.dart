import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tournamentSortingServiceProvider = Provider<TournamentSortingService>((
  ref,
) {
  return TournamentSortingService(ref);
});

class TournamentSortingService {
  final Ref ref;

  TournamentSortingService(this.ref);

  List<GroupEventCardModel> sortAllTours(List<GroupEventCardModel> tours) {
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

  List<GroupEventCardModel> sortUpcomingTours(List<GroupEventCardModel> tours) {
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

      final daysA = _extractDaysFromTimeUntilStart(a.timeUntilStart);
      final daysB = _extractDaysFromTimeUntilStart(b.timeUntilStart);
      final daysComparison = daysA.compareTo(daysB);
      if (daysComparison != 0) return daysComparison;
      // Finally sort by title
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filteredList;
  }

  List<GroupEventCardModel> sortPastTours(List<GroupEventCardModel> tours) {
    final filteredList =
        tours
            .where((t) => t.tourEventCategory == TourEventCategory.completed)
            .toList();

    filteredList.sort((a, b) {
      final endDateA = a.endDate;
      final endDateB = b.endDate;

      // Handle null dates - push them to the bottom
      if (endDateA == null && endDateB == null) {
        // Both null: sort by maxAvgElo (higher first)
        return b.maxAvgElo.compareTo(a.maxAvgElo);
      } else if (endDateA == null) {
        return 1; // a goes to bottom
      } else if (endDateB == null) {
        return -1; // b goes to bottom
      }

      // Sort by end date: most recent first (descending order)
      final dateComparison = endDateB.compareTo(endDateA);

      // If dates are the same, sort by maxAvgElo (higher first)
      if (dateComparison == 0) {
        return b.maxAvgElo.compareTo(a.maxAvgElo);
      }

      return dateComparison;
    });

    return filteredList;
  }

  int _extractDaysFromTimeUntilStart(String txt) {
    if (txt.isEmpty) return 999999;
    final s = txt.trim().toLowerCase().replaceAll('in', '').trim();

    if (s.contains('minute') || s.contains('hour')) return 0;

    final dayMatch = RegExp(r'(\d+)\s*day').firstMatch(s);
    if (dayMatch != null) return int.parse(dayMatch.group(1)!);

    final monMatch = RegExp(r'(\d+)\s*month').firstMatch(s);
    if (monMatch != null) return int.parse(monMatch.group(1)!) * 30;

    final yrMatch = RegExp(r'(\d+)\s*year').firstMatch(s);
    if (yrMatch != null) return int.parse(yrMatch.group(1)!) * 365;

    return 999999;
  }

  List<GroupEventCardModel> sortBasedOnFavorite({
    required List<GroupEventCardModel> tours,
    required List<String> favorites,
  }) {
    if (favorites.isEmpty) {
      return tours; // No favorites, return as-is
    }

    // Separate favorites from non-favorites while preserving order
    final favoriteEvents = <GroupEventCardModel>[];
    final nonFavoriteEvents = <GroupEventCardModel>[];

    for (final tour in tours) {
      if (favorites.contains(tour.id)) {
        favoriteEvents.add(tour);
      } else {
        nonFavoriteEvents.add(tour);
      }
    }

    // Return favorites first, then non-favorites (both in original order)
    return [...favoriteEvents, ...nonFavoriteEvents];
  }
}
