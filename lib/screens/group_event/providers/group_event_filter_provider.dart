import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';

// Filter controller provider
final groupEventFilterProvider =
    AutoDisposeProvider.family<_GroupEventFilterController, GroupEventCategory>(
      (
        ref,
        tournamentCategory,
      ) {
        return _GroupEventFilterController(
          ref: ref,
          tournamentCategory: tournamentCategory,
        );
      },
    );

// Formats provider
final groupEventFormatProvider =
    AutoDisposeFutureProvider.family<List<String>, GroupEventCategory>((
      ref,
      tournamentCategory,
    ) async {
      return ref
          .read(groupEventFilterProvider(tournamentCategory))
          .getFormats();
    });

// Filter controller
class _GroupEventFilterController {
  _GroupEventFilterController({
    required this.ref,
    required this.tournamentCategory,
  });

  final Ref ref;
  final GroupEventCategory tournamentCategory;

  Future<List<String>> getFormats() async {
    final current =
        await ref
            .read(groupBroadcastLocalStorage(GroupEventCategory.current))
            .getGroupBroadcasts();
    final upcoming =
        await ref
            .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
            .getGroupBroadcasts();
    final past =
        await ref
            .read(groupBroadcastLocalStorage(GroupEventCategory.past))
            .getGroupBroadcasts();

    final all = [...current, ...upcoming, ...past];

    final formats =
        all
            .map((t) => t.timeControl?.trim())
            .whereType<String>()
            .where((f) => f.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return formats;
  }

  Future<List<GroupBroadcast>> applyFilter(String selectedFormat) async {
    print('applyFilter called with format: $selectedFormat');
    final groupBroadcast =
        await ref
            .read(groupBroadcastLocalStorage(tournamentCategory))
            .getGroupBroadcasts();
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
    List<String>? format,
    required RangeValues eloRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    print(
      'applyAllFilters called - Format: $format, ELO: ${eloRange.start.round()}-${eloRange.end.round()}, Dates: $startDate to $endDate',
    );

    final groupBroadcast =
        await ref
            .read(groupBroadcastLocalStorage(tournamentCategory))
            .getGroupBroadcasts();

    final filteredTours =
        groupBroadcast.where((tour) {
          print('Checking tour: ${tour.name}, maxAvgElo: ${tour.maxAvgElo}');

          if (format != null && format.isNotEmpty) {
            final tourFormat = tour.timeControl?.trim().toLowerCase();
            if (tourFormat == null ||
                !format.map((f) => f.toLowerCase()).contains(tourFormat)) {
              return false;
            }
          }

          // ELO filter - Only apply if tour has ELO data and range is not default
          final minElo = eloRange.start.round();
          final maxElo = eloRange.end.round();

          if (tour.maxAvgElo != null) {
            if (tour.maxAvgElo! < minElo || tour.maxAvgElo! > maxElo) {
              print(
                'ELO filter failed for ${tour.name}: ${tour.maxAvgElo} not in range $minElo-$maxElo',
              );
              return false;
            }
            print(
              'ELO filter passed for ${tour.name}: ${tour.maxAvgElo} in range $minElo-$maxElo',
            );
          } else {
            // If tour has no ELO data, include it only if range covers typical values
            print(
              'Tour ${tour.name} has no ELO data, including based on default range',
            );
          }

          // Date range filter
          if (startDate != null && tour.dateStart != null) {
            if (tour.dateStart!.isBefore(startDate)) {
              print('Start date filter failed for ${tour.name}');
              return false;
            }
          }

          if (endDate != null && tour.dateEnd != null) {
            final endDatePlusOne = DateTime(
              endDate.year,
              endDate.month,
              endDate.day + 1,
            );
            if (tour.dateEnd!.isAfter(endDatePlusOne)) {
              print('End date filter failed for ${tour.name}');
              return false;
            }
          }

          print('All filters passed for ${tour.name}');
          return true;
        }).toList();

    print(
      'Filtered ${filteredTours.length} tournaments from ${groupBroadcast.length} total',
    );
    return filteredTours;
  }
}
