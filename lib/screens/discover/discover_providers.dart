import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart'
    show GroupEventCategory;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:flutter/material.dart' show RangeValues;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Current live / ongoing broadcasts mapped to event cards for the Discover
/// surface. Deliberately decoupled from the Events-tab category selection so
/// the Discover rails never inherit whatever filter the user left on Events.
final discoverCurrentEventsProvider =
    FutureProvider.autoDispose<List<GroupEventCardModel>>((ref) async {
  final liveIds =
      ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ?? const <String>[];
  final broadcasts = await ref
      .read(groupBroadcastLocalStorage(GroupEventCategory.current))
      .getGroupBroadcasts();
  return [
    for (final b in broadcasts)
      GroupEventCardModel.fromGroupBroadcast(b, liveIds),
  ];
});

/// One synthesized smart-event card per rating tier (GM / IM / FM / CM) whose
/// Elo floor admits at least one current event. Cards are built with the same
/// [SmartEventCardData.fromState] the Events tab uses, and open the existing
/// [SmartEventScreen] unchanged — so the real game aggregation stays canonical.
final discoverSmartTierCardsProvider =
    Provider.autoDispose<List<SmartEventCardData>>((ref) {
  final events =
      ref.watch(discoverCurrentEventsProvider).valueOrNull ?? const [];
  if (events.isEmpty) return const [];

  final cards = <SmartEventCardData>[];
  for (final tier in RatingTierFilter.tiers) {
    final floor = tier.minRating;
    final tierEvents =
        events.where((e) => e.maxAvgElo >= floor).toList(growable: false);
    if (tierEvents.isEmpty) continue;

    final data = SmartEventCardData.fromState(
      filter: FilterPopupState(
        formatsAndStates: const <String>{},
        eloRange: RangeValues(floor.toDouble(), kFilterMaxElo),
      ),
      events: tierEvents,
      source: SmartEventSource.current,
    );
    if (data != null) cards.add(data);
  }
  return cards;
});
