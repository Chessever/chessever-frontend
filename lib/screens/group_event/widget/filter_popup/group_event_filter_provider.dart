import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/material.dart';

enum EventFormat {
  blitz,
  rapid,
  standard;

  String get caption => name[0].toUpperCase() + name.substring(1);
}

enum EventStatus {
  live,
  completed;

  String get caption => name[0].toUpperCase() + name.substring(1);
}

final groupEventFilterProvider =
    AutoDisposeProvider.family<_GroupEventFilterController, GroupEventCategory>(
      (ref, tournamentCategory) {
        return _GroupEventFilterController(
          ref: ref,
          tournamentCategory: tournamentCategory,
        );
      },
    );

class _GroupEventFilterController {
  _GroupEventFilterController({
    required this.ref,
    required this.tournamentCategory,
  });

  final Ref ref;
  final GroupEventCategory tournamentCategory;

  List<String> getReadableFormats() {
    return EventFormat.values.map((e) => e.caption).toList();
  }

  List<String> getFormats() {
    return EventFormat.values.map((e) => e.name).toList();
  }

  List<String> getReadableGameState() {
    return EventStatus.values.map((e) => e.caption).toList();
  }

  List<String> getGameState() {
    return EventStatus.values.map((e) => e.name).toList();
  }

  Future<List<GroupBroadcast>> applyAllFilters({
    List<String>? filters,
    required RangeValues eloRange,
  }) async {
    final groupBroadcast =
        await ref
            .read(groupBroadcastLocalStorage(tournamentCategory))
            .getGroupBroadcasts();

    // Normalize filters
    final filterSet =
        (filters ?? const <String>[])
            .map((f) => f.trim().toLowerCase())
            .toSet();

    // Separate status vs format filters
    final requestedStatuses = <String>{
      EventStatus.live.name,
      EventStatus.completed.name,
    }.intersection(filterSet);

    final requestedFormats = filterSet.difference(requestedStatuses);

    // Fetch live IDs once (avoid per-item await)
    final liveIds = await ref.read(liveGroupBroadcastIdsProvider.future);

    final filteredTours = await Future.wait(
      groupBroadcast.map((tour) async {
        // Status filter: handle live and completed
        bool matchesStatus = true;
        if (requestedStatuses.isNotEmpty) {
          final isLive = liveIds.contains(tour.id);
          final isCompleted = !isLive;

          matchesStatus =
              (requestedStatuses.contains(EventStatus.live.name) && isLive) ||
              (requestedStatuses.contains(EventStatus.completed.name) &&
                  isCompleted);
          if (!matchesStatus) return null;
        }

        // Format filter: blitz/rapid/standard
        bool matchesFormat = true;
        if (requestedFormats.isNotEmpty) {
          final tourFormat = tour.timeControl?.trim().toLowerCase();
          matchesFormat =
              tourFormat != null && requestedFormats.contains(tourFormat);
          if (!matchesFormat) return null;
        }

        // Elo filter (inclusive)
        final minElo = eloRange.start.round();
        final maxElo = eloRange.end.round();
        if (tour.maxAvgElo != null) {
          if (tour.maxAvgElo! < minElo || tour.maxAvgElo! > maxElo) {
            return null;
          }
        }

        return tour;
      }),
    );

    return filteredTours.whereType<GroupBroadcast>().toList();
  }
}
