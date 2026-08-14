import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/utils/event_time_control.dart';

/// THE filter semantics of the home Current/Past lists, extracted so other
/// surfaces (the smart event resolver, search, [applyFiltersToBroadcasts])
/// evaluate the exact same criteria over the exact same fields.
///
/// Semantics: live/completed test against [liveIds]; formats test the
/// broadcast's time control by bucket (`standard`/`classical`, `blitz`/
/// `bullet`); the Elo band tests `max_avg_elo` and lets null-rated
/// broadcasts through (unknown is not a mismatch). Selecting every Time
/// Control chip is the same as selecting none.
List<GroupBroadcast> filterBroadcastsByPopupState(
  List<GroupBroadcast> broadcasts,
  FilterPopupState filter, {
  required List<String> liveIds,
}) {
  final filterSet =
      filter.formatsAndStates
          .map((f) => f.trim().toLowerCase())
          .where((f) => f.isNotEmpty)
          .toSet();

  final requestedStatuses = <String>{
    'live',
    'completed',
  }.intersection(filterSet);
  final requestedFormats = filterSet.difference(requestedStatuses);

  return broadcasts.where((tour) {
    if (requestedStatuses.isNotEmpty) {
      final isLive = liveIds.contains(tour.id);
      final matchesStatus =
          (requestedStatuses.contains('live') && isLive) ||
          (requestedStatuses.contains('completed') && !isLive);
      if (!matchesStatus) return false;
    }

    if (!broadcastMatchesTimeControlFilter(tour.timeControl, requestedFormats)) {
      return false;
    }

    if (filter.hasEloFilter && tour.maxAvgElo != null) {
      final minElo = filter.minElo ?? kFilterMinElo.round();
      final maxElo = filter.maxElo ?? kFilterMaxElo.round();
      if (tour.maxAvgElo! < minElo || tour.maxAvgElo! > maxElo) {
        return false;
      }
    }

    return true;
  }).toList();
}
