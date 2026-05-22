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

  String get caption {
    switch (this) {
      case EventFormat.standard:
        return 'Classical';
      case EventFormat.blitz:
        return 'Blitz';
      case EventFormat.rapid:
        return 'Rapid';
    }
  }
}

enum EventStatus {
  live,
  completed;

  String get caption => name[0].toUpperCase() + name.substring(1);
}

final groupEventFilterProvider =
    AutoDisposeProvider<_GroupEventFilterController>((ref) {
      return _GroupEventFilterController(ref: ref);
    });

class _GroupEventFilterController {
  _GroupEventFilterController({required this.ref});

  final Ref ref;

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
    required GroupEventCategory tournamentCategory,
  }) async {
    final groupBroadcast =
        await ref
            .read(groupBroadcastLocalStorage(tournamentCategory))
            .getGroupBroadcasts();

    // Fetch live IDs once (avoid per-item await)
    final liveIds = await ref.read(liveGroupBroadcastIdsProvider.future);

    return applyFiltersToBroadcasts(
      broadcasts: groupBroadcast,
      filters: filters,
      eloRange: eloRange,
      liveIds: liveIds,
    );
  }

  List<GroupBroadcast> applyFiltersToBroadcasts({
    required List<GroupBroadcast> broadcasts,
    List<String>? filters,
    required RangeValues eloRange,
    required List<String> liveIds,
  }) {
    // Normalize filters
    final filterSet =
        (filters ?? const <String>[])
            .map((f) => f.trim().toLowerCase())
            .where((f) => f.isNotEmpty)
            .toSet();

    // Separate status vs format filters
    final requestedStatuses = <String>{
      EventStatus.live.name,
      EventStatus.completed.name,
    }.intersection(filterSet);

    final requestedFormats = filterSet.difference(requestedStatuses);

    return broadcasts.where((tour) {
      // Status filter: handle live and completed
      if (requestedStatuses.isNotEmpty) {
        final isLive = liveIds.contains(tour.id);
        final isCompleted = !isLive;

        final matchesStatus =
            (requestedStatuses.contains(EventStatus.live.name) && isLive) ||
            (requestedStatuses.contains(EventStatus.completed.name) &&
                isCompleted);
        if (!matchesStatus) return false;
      }

      // Format filter: blitz/rapid/standard
      if (requestedFormats.isNotEmpty) {
        final tourFormat = tour.timeControl?.trim().toLowerCase();
        final matchesFormat =
            tourFormat != null && requestedFormats.contains(tourFormat);
        if (!matchesFormat) return false;
      }

      // Elo filter (inclusive)
      final minElo = eloRange.start.round();
      final maxElo = eloRange.end.round();
      if (tour.maxAvgElo != null) {
        if (tour.maxAvgElo! < minElo || tour.maxAvgElo! > maxElo) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}
