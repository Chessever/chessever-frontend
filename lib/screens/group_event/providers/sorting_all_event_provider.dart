import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tournamentSortingServiceProvider =
    AutoDisposeProvider<TournamentSortingService>((ref) {
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

  List<GroupEventCardModel> sortPastTours(
    List<GroupEventCardModel> tours, {
    bool ascending = false,
  }) {
    var sortedTours = <GroupEventCardModel>[];
    sortedTours = tours;

    sortedTours.sort((a, b) {
      final datesA = _extractDates(a.dates);
      final datesB = _extractDates(b.dates);

      if (datesA == null && datesB == null) return 0;
      if (datesA == null) return 1;
      if (datesB == null) return -1;

      final endDateA = datesA['end']!;
      final endDateB = datesB['end']!;

      final endComparison = endDateA.compareTo(endDateB);

      if (endComparison != 0) {
        return ascending ? endComparison : -endComparison;
      } else {
        final startDateA = datesA['start']!;
        final startDateB = datesB['start']!;
        final startComparison = startDateA.compareTo(startDateB);
        return ascending ? startComparison : -startComparison;
      }
    });

    return sortedTours;
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

  static Map<String, DateTime>? _extractDates(String dateString) {
    try {
      final cleaned = dateString.trim();

      final parts = cleaned.split(',');
      if (parts.length != 2) return null;

      final year = parts[1].trim();
      final datePart = parts[0].trim();

      if (datePart.contains('-')) {
        final rangeParts = datePart.split('-').map((e) => e.trim()).toList();
        if (rangeParts.length != 2) return null;

        final startDateStr = rangeParts[0].trim();
        final endDateStr = rangeParts[1].trim();

        final startParts = startDateStr.split(' ');
        final endParts = endDateStr.split(' ');

        DateTime? startDate;
        DateTime? endDate;

        if (startParts.length == 2) {
          final startMonth = _monthToNumber(startParts[0]);
          final startDay = int.parse(startParts[1]);
          final yearInt = int.parse(year);
          startDate = DateTime(yearInt, startMonth, startDay);

          if (endParts.length == 2) {
            final endDay = int.parse(endParts[0]);
            final endMonth = _monthToNumber(endParts[1]);
            endDate = DateTime(yearInt, endMonth, endDay);
          } else if (endParts.length == 1) {
            final endDay = int.parse(endParts[0]);
            endDate = DateTime(yearInt, startMonth, endDay);
          }
        } else if (startParts.length == 1 && endParts.length == 2) {
          final endDay = int.parse(endParts[0]);
          final endMonth = _monthToNumber(endParts[1]);
          final yearInt = int.parse(year);
          endDate = DateTime(yearInt, endMonth, endDay);

          final startDay = int.parse(startParts[0]);
          startDate = DateTime(yearInt, endMonth, startDay);
        }

        if (startDate == null || endDate == null) return null;

        return {'start': startDate, 'end': endDate};
      } else {
        final date = _parseDate(datePart, year);
        if (date == null) return null;
        return {'start': date, 'end': date};
      }
    } catch (e) {
      print('Error parsing date "$dateString": $e');
      return null;
    }
  }

  static DateTime? _parseDate(String datePart, String year) {
    try {
      final parts = datePart.trim().split(' ');

      if (parts.length == 2) {
        final firstPart = parts[0];
        final secondPart = parts[1];

        final firstNum = int.tryParse(firstPart);

        if (firstNum != null) {
          final day = firstNum;
          final month = _monthToNumber(secondPart);
          final yearInt = int.parse(year);
          return DateTime(yearInt, month, day);
        } else {
          final month = _monthToNumber(firstPart);
          final day = int.parse(secondPart);
          final yearInt = int.parse(year);
          return DateTime(yearInt, month, day);
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static int _monthToNumber(String month) {
    final monthMap = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };

    return monthMap[month] ?? 1;
  }
}
