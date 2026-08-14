import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/event_filter_matching.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
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
    return filterBroadcastsByPopupState(
      broadcasts,
      FilterPopupState(
        formatsAndStates: {
          for (final value in filters ?? const <String>[])
            if (value.trim().isNotEmpty) value.trim().toLowerCase(),
        },
        eloRange: eloRange,
      ),
      liveIds: liveIds,
    );
  }
}
