import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';

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

  List<GroupEventCardModel> sortPastTours({
    required List<GroupEventCardModel> tours,
    required List<GroupBroadcast> groupBroadcasts,
  }) {
    final now = DateTime.now();

    final filteredList =
        tours
            .where((t) => t.tourEventCategory == TourEventCategory.completed)
            .toList();

    filteredList.sort((a, b) {
      final broadcastA = groupBroadcasts.firstWhere(
        (broadcast) => broadcast.id == a.id,
        orElse: () => groupBroadcasts.first,
      );
      final broadcastB = groupBroadcasts.firstWhere(
        (broadcast) => broadcast.id == b.id,
        orElse: () => groupBroadcasts.first,
      );

      final endDateA = broadcastA.dateEnd;
      final endDateB = broadcastB.dateEnd;

      // Handle null dates safely
      if (endDateA == null && endDateB == null) {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      } else if (endDateA == null) {
        return 1;
      } else if (endDateB == null) {
        return -1;
      }

      // Calculate the absolute difference from current date
      final diffA = (now.difference(endDateA)).abs();
      final diffB = (now.difference(endDateB)).abs();

      // Sort by whichever date is closer to now (smaller difference)
      return diffA.compareTo(diffB);
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
    final hasFavorites = favorites.isNotEmpty;

    var sortedEvents = tours.toList();
    sortedEvents.sort((a, b) {
      final isFavoriteA = favorites.contains(a.id);
      final isFavoriteB = favorites.contains(b.id);

      // FIRST PRIORITY: Favorites (only for non-completed tournaments)

      if (hasFavorites) {
        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

      // SECOND PRIORITY: ELO sorting (same logic as your other methods)
      final isHighEloA = a.maxAvgElo > 3200;
      final isHighEloB = b.maxAvgElo > 3200;

      // If one has high ELO and the other doesn't, put high ELO at the end
      if (isHighEloA && !isHighEloB) return 1;
      if (!isHighEloA && isHighEloB) return -1;

      // If both are high ELO or both are normal ELO, sort by ELO descending
      final eloComparison = b.maxAvgElo.compareTo(a.maxAvgElo);
      if (eloComparison != 0) return eloComparison;

      final daysA = _extractDaysFromTimeUntilStart(a.timeUntilStart);
      final daysB = _extractDaysFromTimeUntilStart(b.timeUntilStart);
      final daysComparison = daysA.compareTo(daysB);
      if (daysComparison != 0) return daysComparison;

      // THIRD PRIORITY: Title alphabetically
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return sortedEvents;
  }
}
