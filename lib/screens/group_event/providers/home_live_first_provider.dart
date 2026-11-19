import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the home tabs list their live events first (Trello #1420).
///
/// One flag for both home tabs, so they always agree: the Events tab orders
/// Current, the list live events belong to, and the For You tab (labelled
/// Home) orders its Today feed (`ForYouNotifier`). Kept for the session, like
/// the game lists' Live first (`gameListLiveFirstProvider`). The order is laid
/// over each list's own ranking ([liveEventsFirst]), so turning it off
/// restores that ranking exactly.
final homeEventsLiveFirstProvider = StateProvider<bool>((ref) => false);

/// Snack shown when Live first is pressed while no event is in play.
const String kNoLiveEventsRightNowMessage = 'No live events right now';

/// Snack shown when Live first is pressed while events are in play but the
/// list's filters keep every one of them out. The button counts the events
/// in play, so "2 live" must not be answered with "No live events".
const String kNoLiveEventsMatchFiltersMessage =
    'No live events match your filters';

/// What a press of Live first that found nothing to lift says: that nothing
/// is live, or, with events in play ([liveIds]) and [filters] narrowing the
/// list, that the filters keep them out.
String noLiveEventsMessage({
  required Set<String> liveIds,
  required FilterPopupState filters,
}) {
  final narrowed =
      filters.formatsAndStates.isNotEmpty ||
      filters.hasEloFilter ||
      !filters.eco.isAll;
  return liveIds.isNotEmpty && narrowed
      ? kNoLiveEventsMatchFiltersMessage
      : kNoLiveEventsRightNowMessage;
}

/// Whether [event] is live, by the test its card uses for the LIVE label:
/// its own category, or the strict live-ids stream, which can lead the
/// category by a refresh as a round starts.
bool isLiveEvent(GroupEventCardModel event, Set<String> liveIds) =>
    event.tourEventCategory == TourEventCategory.live ||
    liveIds.contains(event.id);

/// [events] with the live ones ([isLiveEvent]) first, keeping the given order
/// on both sides of the split. Returns the same list when nothing (or
/// everything) is live.
List<GroupEventCardModel> liveEventsFirst(
  List<GroupEventCardModel> events,
  Set<String> liveIds,
) {
  final live = <GroupEventCardModel>[];
  final rest = <GroupEventCardModel>[];
  for (final event in events) {
    (isLiveEvent(event, liveIds) ? live : rest).add(event);
  }
  if (live.isEmpty || rest.isEmpty) return events;
  return [...live, ...rest];
}

/// Current as the Events tab shows it: ranked with favourites and hearts on
/// top ([TournamentSortingService.sortBasedOnFavorite]), then, while Live
/// first is on, its live events above all ([liveEventsFirst]).
///
/// The list arrives from its provider with the live events already first,
/// but the favourite ranking here re-sorts it from scratch, so Live first has
/// to be laid over that ranking again or a starred event would climb back
/// above the live ones.
List<GroupEventCardModel> currentEventsDisplayOrder({
  required List<GroupEventCardModel> events,
  required TournamentSortingService sorter,
  required List<String> favorites,
  Map<String, EventFavoritePlayers>? eventFavoritePlayersMap,
  Map<String, DateTime>? favoriteTimestamps,
  required bool liveFirst,
  required Set<String> liveIds,
}) {
  final ranked = sorter.sortBasedOnFavorite(
    tours: events,
    favorites: favorites,
    eventFavoritePlayersMap: eventFavoritePlayersMap,
    favoriteTimestamps: favoriteTimestamps,
  );
  return liveFirst ? liveEventsFirst(ranked, liveIds) : ranked;
}

/// The ids of the events in play: the strict live-ids stream once it has a
/// value ([strict]), else the copy the events list keeps of it ([mirror]).
Set<String> homeLiveEventIds({
  required List<String>? strict,
  required List<String> mirror,
}) => (strict ?? mirror).toSet();

/// Whether anything is in play. With the Current list at hand
/// ([currentEvents]) the answer is about that list as it is shown (filters
/// applied); without it, about [liveIds] alone.
bool anyLiveEvent({
  required Set<String> liveIds,
  List<GroupEventCardModel>? currentEvents,
}) {
  if (currentEvents == null) return liveIds.isNotEmpty;
  return currentEvents.any((event) => isLiveEvent(event, liveIds));
}

/// Presses Live first on the home Events bar and returns whether it turned
/// on.
///
/// Turning it off always works. Turning it on needs an event in play: with
/// none, it stays off and a snack says there are no live events right now
/// (or, with events in play that the filters keep out of Current, that none
/// match the filters), so the tap is never a silent no-op. Turned on from
/// Past or Upcoming, it opens Current, the list it orders.
bool pressHomeEventsLiveFirst({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final flag = ref.read(homeEventsLiveFirstProvider.notifier);
  if (flag.state) {
    flag.state = false;
    return false;
  }
  final category = ref.read(selectedGroupCategoryProvider);
  final liveIds = homeLiveEventIds(
    strict: ref.read(liveGroupBroadcastIdsProvider).valueOrNull,
    mirror: ref.read(liveBroadcastIdsProvider),
  );
  // The list on screen, when it is Current and already loaded. Never builds
  // the list just to ask.
  final currentEvents =
      category == GroupEventCategory.current &&
          ref.exists(groupEventScreenProvider)
      ? ref.read(groupEventScreenProvider).valueOrNull
      : null;
  // From another segment, the button's own count answers once it is known:
  // Current's events in play under the filters, what a press would lift.
  final count =
      currentEvents == null && ref.exists(eventsLiveEventCountProvider)
      ? ref.read(eventsLiveEventCountProvider)
      : null;
  final hasLive = count != null
      ? count > 0
      : anyLiveEvent(liveIds: liveIds, currentEvents: currentEvents);
  if (!hasLive) {
    showAppSnack(
      context,
      noLiveEventsMessage(
        liveIds: liveIds,
        filters: ref.read(currentPastAppliedFilterProvider),
      ),
    );
    return false;
  }
  flag.state = true;
  if (category != GroupEventCategory.current) {
    ref.read(selectedGroupCategoryProvider.notifier).state =
        GroupEventCategory.current;
  }
  return true;
}

/// Presses Live first on the For You (Home) bar and returns whether this
/// press turned it on.
///
/// The same flag as the Events bar ([homeEventsLiveFirstProvider]), with the
/// same rules over the Today feed: off always works; on needs an event in
/// play that the feed's filters let through, else it stays off and a snack
/// says which of the two is missing ([noLiveEventsMessage]). The feed pages
/// its events in, so one in play can sit below the loaded pages; when no
/// loaded event is live but some event is, the feed fetches those first
/// ([ForYouNotifier.hasLiveEvent]) and the press waits for that answer.
Future<bool> pressForYouLiveFirst({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final flag = ref.read(homeEventsLiveFirstProvider.notifier);
  if (flag.state) {
    flag.state = false;
    return false;
  }
  final feed = ref.read(forYouEventsProvider.notifier);
  final hasLive = await feed.hasLiveEvent();
  if (!context.mounted) return false;
  if (!hasLive) {
    showAppSnack(
      context,
      noLiveEventsMessage(
        liveIds: homeLiveEventIds(
          strict: ref.read(liveGroupBroadcastIdsProvider).valueOrNull,
          mirror: ref.read(liveBroadcastIdsProvider),
        ),
        filters: ref.read(forYouAppliedFilterProvider),
      ),
    );
    return false;
  }
  // Already turned on while the feed was asked (the Events bar).
  if (flag.state) return false;
  flag.state = true;
  return true;
}

/// The ids of the events in play ([homeLiveEventIds]) as one value that is
/// equal to the last one when the set is, so what reads it is not rebuilt
/// on every identical emission.
@immutable
class HomeLiveEventIds {
  const HomeLiveEventIds(this.ids);

  final Set<String> ids;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeLiveEventIds && setEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAllUnordered(ids);
}

/// The events in play, by the strict live-ids stream once it has a value,
/// else the events list's copy of it ([homeLiveEventIds]).
final homeLiveEventIdsProvider = Provider.autoDispose<HomeLiveEventIds>((ref) {
  return HomeLiveEventIds(
    homeLiveEventIds(
      strict: ref.watch(liveGroupBroadcastIdsProvider).valueOrNull,
      mirror: ref.watch(liveBroadcastIdsProvider),
    ),
  );
});

/// Current's events in play under the Current/Past filters: the events the
/// Events lists' Live first lifts. Fetched by id from Current
/// (`group_broadcasts_current`, the list's own source) whenever the live
/// set or the filters change; a refetch keeps the last answer until it lands.
final _eventsLiveCurrentIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final live = ref.watch(homeLiveEventIdsProvider).ids;
  final filters = ref.watch(currentPastAppliedFilterProvider);
  if (live.isEmpty) return const <String>{};
  final liveIds = live.toList(growable: false)..sort();
  final current = await ref
      .read(groupBroadcastRepositoryProvider)
      .getCurrentGroupBroadcastsByIds(liveIds);
  return {
    for (final broadcast in filterBroadcastsByPopupState(
      current,
      filters,
      liveIds: liveIds,
    ))
      broadcast.id,
  };
});

/// How many events the Events lists' Live first lifts: Current's events in
/// play, under the filters Current shows ("See 3 live"). 0 with nothing in
/// play; null until the first answer, which the capsule reads as "See
/// live".
final eventsLiveEventCountProvider = Provider.autoDispose<int?>((ref) {
  if (ref.watch(homeLiveEventIdsProvider).ids.isEmpty) return 0;
  return ref.watch(_eventsLiveCurrentIdsProvider).valueOrNull?.length;
});

/// How many events Today's Live first lifts: the loaded events in play and
/// the ones in play below the loaded pages that Today's filters let through
/// ([ForYouState.liveEventIds]), less any whose section hides itself for
/// want of boards, so the count is what a press brings into view. 0 with
/// nothing in play; null while the feed does not know yet ("See live").
final todayLiveEventCountProvider = Provider.autoDispose<int?>((ref) {
  if (ref.watch(homeLiveEventIdsProvider).ids.isEmpty) return 0;
  final ids = ref.watch(
    forYouEventsProvider.select((state) => state.liveEventIds),
  );
  if (ids == null) return null;
  if (ids.isEmpty) return 0;
  return ref.watch(
    forYouTopGamesSnapshotCacheProvider.select(
      (snapshots) => ids.where((id) => snapshots[id]?.hasGames != false).length,
    ),
  );
});

/// Whether a home Live first button is there: while an event it would lift
/// is in play, while the count is not known yet (it reads "See live"), and
/// while it is on, so a flag left on can always be turned off.
bool showsHomeLiveFirst({required int? liveCount, required bool on}) =>
    on || liveCount == null || liveCount > 0;
