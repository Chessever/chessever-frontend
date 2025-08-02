import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';

// Filter controller provider
final tourFormatRepositoryProvider =
AutoDisposeProvider.family<FilterController, TournamentCategory>((
    ref,
    tournamentCategory,
    ) {
  return FilterController(ref: ref, tournamentCategory: tournamentCategory);
});

// Formats provider
final tourFormatsProvider =
AutoDisposeFutureProvider.family<List<String>, TournamentCategory>((
    ref,
    tournamentCategory,
    ) async {
  return ref
      .read(tourFormatRepositoryProvider(tournamentCategory))
      .getFormats();
});

// Filter controller
class FilterController {
  FilterController({required this.ref, required this.tournamentCategory});

  final Ref ref;
  final TournamentCategory tournamentCategory;

  Future<List<String>> getFormats() async {
    final groupBroadcast =
    await ref
        .read(groupBroadcastLocalStorage(tournamentCategory))
        .getGroupBroadcasts();
    final formats =
    groupBroadcast
        .map((tour) => tour.timeControl?.trim())
        .whereType<String>()
        .where((format) => format.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['All Formats', ...formats];
  }

  Future<List<GroupBroadcast>> applyFilter(String selectedFormat) async {
    print('applyFilter called with format: $selectedFormat');
    final groupBroadcast = await ref.read(groupBroadcastLocalStorage(tournamentCategory)).getGroupBroadcasts();
    final filteredTours =
    selectedFormat == 'All Formats'
        ? groupBroadcast
        : groupBroadcast.where((tour) {
      final format = tour.timeControl?.trim().toLowerCase();
      final selected = selectedFormat.trim().toLowerCase();
      return format == selected;
    }).toList();

    return filteredTours;
  }

  // Enhanced filter method with all filters
  Future<List<GroupBroadcast>> applyAllFilters({
    required String format,
    required RangeValues eloRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    print('applyAllFilters called - Format: $format, ELO: ${eloRange.start.round()}-${eloRange.end.round()}, Dates: $startDate to $endDate');

    final groupBroadcast = await ref.read(groupBroadcastLocalStorage(tournamentCategory)).getGroupBroadcasts();

    final filteredTours = groupBroadcast.where((tour) {
      print('Checking tour: ${tour.name}, maxAvgElo: ${tour.maxAvgElo}');

      // Format filter
      if (format != 'All Formats') {
        final tourFormat = tour.timeControl?.trim().toLowerCase();
        final selectedFormat = format.trim().toLowerCase();
        if (tourFormat != selectedFormat) {
          print('Format filter failed for ${tour.name}');
          return false;
        }
      }

      // ELO filter - Only apply if tour has ELO data and range is not default
      final minElo = eloRange.start.round();
      final maxElo = eloRange.end.round();

      if (tour.maxAvgElo != null) {
        if (tour.maxAvgElo! < minElo || tour.maxAvgElo! > maxElo) {
          print('ELO filter failed for ${tour.name}: ${tour.maxAvgElo} not in range $minElo-$maxElo');
          return false;
        }
        print('ELO filter passed for ${tour.name}: ${tour.maxAvgElo} in range $minElo-$maxElo');
      } else {
        // If tour has no ELO data, include it only if range covers typical values
        print('Tour ${tour.name} has no ELO data, including based on default range');
      }

      // Date range filter
      if (startDate != null && tour.dateStart != null) {
        if (tour.dateStart!.isBefore(startDate)) {
          print('Start date filter failed for ${tour.name}');
          return false;
        }
      }

      if (endDate != null && tour.dateEnd != null) {
        final endDatePlusOne = DateTime(endDate.year, endDate.month, endDate.day + 1);
        if (tour.dateEnd!.isAfter(endDatePlusOne)) {
          print('End date filter failed for ${tour.name}');
          return false;
        }
      }

      print('All filters passed for ${tour.name}');
      return true;
    }).toList();

    print('Filtered ${filteredTours.length} tournaments from ${groupBroadcast.length} total');
    return filteredTours;
  }
}