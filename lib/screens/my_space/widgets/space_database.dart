import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart'
    show discoveryShortEventName;
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoverySmartEventMembersProvider;
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart'
    show LiveGamesBatchKey;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryType, discoveryType;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventRequestFromSpaceShortcut, smartEventSpaceDraft;
import 'package:chessever2/screens/library/providers/library_folders_provider.dart'
    show kMiniaturesFolder;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/actions/space_player_actions.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_prep_screen.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_game_card_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_opening_card.dart';
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart';
import 'package:chessever2/screens/my_space/widgets/space_rail.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_header.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart'
    show liveBatchKeysForGames;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart'
    show smartEventCardSummary, watchSmartEventLive;
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

// ------------------------------------------------------------------ groups

/// One group of My Space: the saved things of one type, in the order the
/// page shows them.
typedef SpaceDatabaseGroup = ({
  SpaceSection section,
  List<SpaceShortcut> items,
});

/// The order the groups stand in on the page. Smart events come last, right
/// above the tile that builds one.
const List<SpaceSection> kSpaceDatabaseOrder = [
  SpaceSection.events,
  SpaceSection.players,
  SpaceSection.games,
  SpaceSection.openings,
  SpaceSection.library,
  SpaceSection.links,
  SpaceSection.smartEvents,
];

/// How many Smart Events the page stacks before See all takes over: the
/// one group that stays a vertical stack of full-width cards.
const int kSpaceSmartEventsShown = 2;

/// Whether a saved thing belongs on My Space's groups: My Likes has its own
/// tile, and streak cards stay out while streaks are hidden.
bool spaceShowsInDatabase(SpaceShortcut s) =>
    s.kind != SpaceShortcutKind.likes &&
    (FeatureFlags.streaks || s.kind != SpaceShortcutKind.streak);

/// The event and round pins that are live, by key.
Set<String> spaceLiveKeys(
  Iterable<SpaceShortcut> list, {
  required Iterable<String> liveEventIds,
  required Iterable<String> liveRoundIds,
}) {
  final events = liveEventIds.toSet();
  final rounds = liveRoundIds.toSet();
  return {
    for (final s in list)
      if ((s.kind == SpaceShortcutKind.event &&
              (events.contains(spaceEventIdOf(s)) ||
                  events.contains(s.targetId))) ||
          (s.kind == SpaceShortcutKind.round && rounds.contains(s.targetId)))
        s.key,
  };
}

/// [list] (in store order) as My Space's groups: typed, in
/// [kSpaceDatabaseOrder], empty ones left out. Events whose key is in
/// [liveFirst] lead their group, each class keeping store order. [players],
/// when given, is the Players group as it stands (the follows and the pins,
/// [spacePlayersProvider]) in place of its pins alone.
List<SpaceDatabaseGroup> spaceDatabaseGroups(
  List<SpaceShortcut> list, {
  Set<String> liveFirst = const {},
  List<SpaceShortcut>? players,
}) {
  final bySection = <SpaceSection, List<SpaceShortcut>>{};
  for (final s in list) {
    if (!spaceShowsInDatabase(s)) continue;
    (bySection[s.section] ??= <SpaceShortcut>[]).add(s);
  }
  if (players != null) bySection[SpaceSection.players] = players;
  final events = bySection[SpaceSection.events];
  if (events != null && liveFirst.isNotEmpty) {
    bySection[SpaceSection.events] = [
      for (final s in events)
        if (liveFirst.contains(s.key)) s,
      for (final s in events)
        if (!liveFirst.contains(s.key)) s,
    ];
  }
  return [
    for (final section in kSpaceDatabaseOrder)
      if (bySection[section] case final items? when items.isNotEmpty)
        (section: section, items: items),
  ];
}

/// The saved events that were live when the page first learned what was
/// live this session: they lead the Events group until a pull to refresh.
/// An event that goes live later keeps its place (it still reads LIVE and
/// shows its boards), so nothing jumps under the reader's finger.
final spaceLiveFirstLatchProvider = StateProvider<Set<String>?>((ref) => null);

/// What My Space shows: the saved things in their groups, the Players group
/// holding the followed players too. Null until the saved list has loaded;
/// a list that failed to load reads as empty.
final spaceDatabaseGroupsProvider =
    Provider.autoDispose<List<SpaceDatabaseGroup>?>((ref) {
      final saved = ref.watch(spaceShortcutsProvider);
      final list = saved.valueOrNull;
      if (list == null) return saved.hasError ? const [] : null;
      final latch = ref.watch(spaceLiveFirstLatchProvider);
      // Watched even while latched, so the live feeds stay subscribed and a
      // cleared latch (pull to refresh) reads them at once.
      final liveEvents = ref.watch(liveGroupBroadcastIdsProvider).valueOrNull;
      final liveRounds = ref.watch(liveRoundsIdProvider).valueOrNull;
      // Until the latch is taken, lead with what is live now, so taking it
      // changes nothing on screen.
      final liveFirst =
          latch ??
          spaceLiveKeys(
            list,
            liveEventIds: liveEvents ?? const <String>[],
            liveRoundIds: liveRounds ?? const <String>[],
          );
      final players = ref.watch(spacePlayersProvider);
      return spaceDatabaseGroups(
        list,
        liveFirst: liveFirst,
        players: players == null ? null : [for (final e in players) e.shortcut],
      );
    });

/// Takes the live-first latch once both live feeds have answered. Called
/// from the page's build; the write lands after the frame.
void spaceTakeLiveFirstLatch(WidgetRef ref) {
  if (ref.read(spaceLiveFirstLatchProvider) != null) return;
  final events = ref.watch(liveGroupBroadcastIdsProvider).valueOrNull;
  final rounds = ref.watch(liveRoundsIdProvider).valueOrNull;
  final list = ref.watch(spaceShortcutsProvider).valueOrNull;
  if (events == null || rounds == null || list == null) return;
  final keys = spaceLiveKeys(list, liveEventIds: events, liveRoundIds: rounds);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final latch = ref.read(spaceLiveFirstLatchProvider.notifier);
    if (latch.state == null) latch.state = keys;
  });
}

// ------------------------------------------------------------------ events

/// The card model an event shortcut carries itself: what the event card
/// showed when it was saved. Enough to draw the card at once, and all a
/// calendar or database-only event ever has.
GroupEventCardModel spaceEventCardModelFromShortcut(SpaceShortcut s) {
  String? str(String key) {
    final v = s.params[key];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  // What the card showed when it was saved. A saved "live" is not a claim
  // about now: the live feed says LIVE, so the snapshot reads as running.
  TourEventCategory category() {
    final raw = str('category');
    if (raw == TourEventCategory.live.name) return TourEventCategory.ongoing;
    for (final c in TourEventCategory.values) {
      if (c.name == raw) return c;
    }
    return TourEventCategory.completed;
  }

  final community =
      str('source') == 'calendar' ||
      str('eventSource') == EventSource.communityEvent.name;
  return GroupEventCardModel(
    id: s.targetId,
    title: s.title,
    dates: str('dates') ?? s.subtitle ?? '',
    maxAvgElo: 0,
    timeUntilStart: '',
    tourEventCategory: category(),
    timeControl: str('timeControl') ?? '',
    endDate: null,
    startDate: null,
    location: str('location'),
    eventSource: community
        ? EventSource.communityEvent
        : EventSource.lichessBroadcast,
  );
}

/// Whether an event shortcut is a broadcast the server can refresh. Calendar
/// and database-only events are not.
bool spaceIsBroadcastEvent(SpaceShortcut s) {
  if (s.kind != SpaceShortcutKind.event) return false;
  final id = s.targetId;
  if (s.params['source'] == 'calendar') return false;
  if (s.params['eventSource'] == EventSource.communityEvent.name) return false;
  return !id.startsWith('gamebase') && !id.startsWith('cal_event_');
}

// ------------------------------------------------------------------ view

/// Opens the whole of one group: its See all page, or for Openings My Prep
/// on its Openings tab, where the saved lines live. What a group's name and
/// its See all both do.
void spaceOpenGroup(BuildContext context, SpaceSection section) {
  HapticFeedbackService.navigation();
  if (section == SpaceSection.openings) {
    unawaited(MyPrepScreen.open(context, initialTab: MyPrepScreen.openingsTab));
    return;
  }
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpaceSectionScreen(section: section, pinsOnly: true),
      ),
    ),
  );
}

/// One group of My Space: the hub's section head (a tappable name, the
/// count, See all) over the group as one sideways rail of the cards the rest
/// of the app gives that kind of thing, loading more as it nears its end.
/// Smart events alone stay a short stack of full-width cards. [gutter] is
/// the page's side inset; the rail runs past it to the screen edge.
class SpaceDatabaseGroupView extends ConsumerWidget {
  const SpaceDatabaseGroupView({
    super.key,
    required this.group,
    required this.gutter,
  });

  final SpaceDatabaseGroup group;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = group.section;
    final items = group.items;
    final Widget body = switch (section) {
      SpaceSection.events => _EventsRail(items: items, gutter: gutter),
      SpaceSection.players => _PlayersRail(gutter: gutter),
      SpaceSection.games => _GamesRail(items: items, gutter: gutter),
      SpaceSection.openings => _OpeningsRail(items: items, gutter: gutter),
      SpaceSection.library => _RowsRail(
        items: items,
        gutter: gutter,
        library: true,
      ),
      SpaceSection.links => _RowsRail(items: items, gutter: gutter),
      SpaceSection.smartEvents => Padding(
        padding: EdgeInsets.fromLTRB(gutter, 4.sp, gutter, 0),
        child: _SmartEventsBody(
          shown: items.take(kSpaceSmartEventsShown).toList(),
        ),
      ),
      SpaceSection.likes => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SpaceSectionHeader(
          key: ValueKey<String>('space_header_${section.name}'),
          title: spaceGroupTitle(section),
          count: items.length,
          gutter: gutter,
          onSeeAll: () => spaceOpenGroup(context, section),
        ),
        body,
      ],
    );
  }
}

/// A live batch over the [shown] games of [games] from [start] (the cards
/// drawn), one channel for them; the games past them never subscribe.
LiveGamesBatchKey? Function(int index) _batchFor(
  List<GamesTourModel> games,
  String scope, {
  required int shown,
  int start = 0,
}) {
  final end = math.min(games.length, start + shown);
  final drawn = games.sublist(math.min(start, end), end);
  final keys = liveBatchKeysForGames(games: drawn, scopePrefix: scope);
  return (index) =>
      index >= start && index < end ? keys[games[index].gameId] : null;
}

/// How many of [length] games a vertical preview draws in [mode] (See all's
/// live boards under an event).
int _previewCount(GamesListViewMode mode, int length) =>
    DiscoveryGameList.shownFor(
      mode,
      length,
      limit: kDiscoveryPreviewCards,
      boardLimit: kDiscoveryPreviewBoards,
    );

// ------------------------------------------------------------------ events

/// What the Events group knows about its saved events, page by page: their
/// fresh card models (one read per page), which are live now, and those
/// events' current boards (one read per page's live events). With [pages]
/// null (See all) every event is one page.
///
/// The first page draws at once from what each pin saved; a later page
/// joins once its read has answered, [loading] meanwhile. The Players group
/// reads the Events rail's loaded pages the same way (the same provider
/// keys), to leave out the boards the Events rail already draws.
class _SavedEvents {
  _SavedEvents(WidgetRef ref, List<SpaceShortcut> items, {int? pages}) {
    _liveIds = {...?ref.watch(liveGroupBroadcastIdsProvider).valueOrNull};
    final size = pages == null ? math.max(1, items.length) : kSpaceRailPage;
    final asked = pages ?? 1;
    final chunks = <List<SpaceShortcut>>[];
    for (var p = 0; p < asked; p++) {
      final page = items.skip(p * size).take(size).toList();
      if (page.isEmpty) break;
      final ids = SpaceIds([
        for (final s in page)
          if (spaceIsBroadcastEvent(s)) spaceEventIdOf(s),
      ]);
      if (!ids.isEmpty) {
        final read = ref.watch(spaceEventBroadcastsProvider(ids));
        if (p > 0 && !read.hasValue && !read.hasError) {
          loading = true;
          break;
        }
        models.addAll(ref.watch(spaceEventCardModelsProvider(ids)));
      }
      chunks.add(page);
    }
    shown = [for (final c in chunks) ...c];
    hasMore = shown.length < items.length;
    for (final page in chunks) {
      final live = SpaceIds([
        for (final s in page)
          if (isLive(s)) spaceEventIdOf(s),
      ]);
      if (live.isEmpty) continue;
      final read = ref.watch(spaceLiveEventGamesProvider(live));
      for (final id in live.ids) {
        _boards[id] = read;
        _readOf[id] = live;
      }
    }
  }

  late final List<SpaceShortcut> shown;
  late final bool hasMore;
  bool loading = false;
  final Map<String, GroupEventCardModel> models = {};
  late final Set<String> _liveIds;
  final Map<String, AsyncValue<SpaceLiveEventGames>> _boards = {};
  final Map<String, SpaceIds> _readOf = {};

  GroupEventCardModel modelOf(SpaceShortcut s) =>
      models[spaceEventIdOf(s)] ?? spaceEventCardModelFromShortcut(s);

  /// Live by the live feed, or by the fresh model once it has landed; never
  /// by the category saved with the shortcut.
  bool isLive(SpaceShortcut s) {
    if (!spaceIsBroadcastEvent(s)) return false;
    final id = spaceEventIdOf(s);
    return _liveIds.contains(id) ||
        models[id]?.tourEventCategory == TourEventCategory.live;
  }

  /// The live events shown, by broadcast id.
  Iterable<String> get live => _boards.keys;

  bool boardsLoading(String id) {
    final read = _boards[id];
    return read != null && !read.hasValue && !read.hasError;
  }

  bool boardsFailed(String id) {
    final read = _boards[id];
    if (read == null) return false;
    return read.hasError || (read.valueOrNull?.failed.contains(id) ?? false);
  }

  /// Whether every live event's boards have answered.
  bool get boardsSettled =>
      _boards.values.every((read) => read.hasValue || read.hasError);

  /// [id]'s boards, when they have loaded.
  List<GamesTourModel> gamesOf(String id) =>
      _boards[id]?.valueOrNull?.byEvent[id]?.visibleGames ??
      const <GamesTourModel>[];

  /// The ids of every board drawn after the shown live events.
  Set<String> get drawnGameIds => {
    for (final id in live)
      for (final g in gamesOf(id)) g.gameId,
  };

  void retry(WidgetRef ref, String id) {
    HapticFeedbackService.buttonPress();
    final read = _readOf[id];
    if (read != null) ref.invalidate(spaceLiveEventGamesProvider(read));
  }
}

/// A saved event's own card (a round's row).
Widget _savedEventCard(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
  _SavedEvents saved,
) {
  if (s.kind == SpaceShortcutKind.round) {
    return SpaceSavedRow(
      shortcut: s,
      meta: _RoundMeta(shortcut: s),
    );
  }
  return EventCard(
    key: ValueKey<String>('space_event_${s.key}'),
    tourEventCardModel: saved.modelOf(s),
    heroTagSuffix: '_myspace',
    forceCompactLayout: true,
    onTap: () => openSpaceShortcut(context, ref, s),
  );
}

/// The Players group's rail of faces and, under it, the rail of the games
/// the shown players are playing (only while there are any). Two rails
/// rather than one row: a face is a small circle in a strip of circles, and
/// a board card among them would stand the whole strip in a row several
/// times its height. Each game is labelled with who is playing, so the two
/// never need to scroll together. The pair keeps its element order, so the
/// faces never remount as the live games come and go.
Widget _withLiveRail(Widget main, Widget? live) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: [main, ?live],
);

/// The room over a live rail: the main rail's own air under its cards
/// already parts the two, so the live games' labels sit close enough to read
/// as the same group.
const double _liveRailAirTop = 4;

/// The Events group: one rail of the saved events, ten a page. A live
/// event stands as its card over its current boards (the viewer's game
/// cards, labelled with the event), the card holding at the gutter while
/// its boards scroll under it ([SpaceRailStickyLead]): an event's boards
/// always stand under their own event, and the next event's card arrives
/// with the next event's boards. See all's order, turned on its side. An
/// event's boards join as its page loads.
///
/// Beside a live event, the events that are not live stand stacked, as many
/// to a column as fill a live event's height, so the rail holds one height
/// with no empty band under a lone card. With no live event, each event is
/// one card of the rail.
///
/// An event card stands up to [kSpaceRailEventWideMax] wide and never
/// narrows to fit one more on the screen, so its dates are never cut to
/// make room.
class _EventsRail extends ConsumerStatefulWidget {
  const _EventsRail({required this.items, required this.gutter});

  final List<SpaceShortcut> items;
  final double gutter;

  @override
  ConsumerState<_EventsRail> createState() => _EventsRailState();
}

class _EventsRailState extends ConsumerState<_EventsRail> with SpaceRailPaging {
  @override
  String get pagingId => 'events';

  @override
  Widget build(BuildContext context) {
    final saved = _SavedEvents(ref, widget.items, pages: pages);
    final mode = ref.watch(gamesListViewModeProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final estimate = spaceRailMetricsFor(
          context,
          viewport: viewport,
          gutter: widget.gutter,
          mode: mode,
          wideMax: kSpaceRailEventWideMax,
          wideNarrows: false,
        );
        return SpaceRail(
          storageId: 'events',
          items: _items(saved, estimate),
          gutter: widget.gutter,
          labelledGames: true,
          hasMore: saved.hasMore,
          loading: saved.loading,
          trailingSlot: SpaceRailSlot.wide,
          onLoadMore: loadMore,
          wideMax: kSpaceRailEventWideMax,
          wideNarrows: false,
        );
      },
    );
  }

  List<SpaceRailItem> _items(_SavedEvents saved, SpaceRailMetrics estimate) {
    final boardsOf = <String, _EventBoards>{
      for (final s in saved.shown)
        if (saved.isLive(s))
          if (_eventBoards(s, saved) case final boards?) s.key: boards,
    };
    // How many cards stand in a column beside a live event: as many as
    // its card over its boards is tall.
    final card = estimate.estimate(SpaceRailSlot.wide);
    final live = estimate.estimate(SpaceRailSlot.group);
    final perColumn = boardsOf.isEmpty
        ? 1
        : math.max(1, ((live + estimate.gap) / (card + estimate.gap)).floor());

    final items = <SpaceRailItem>[];
    var run = <SpaceShortcut>[];
    void closeRun() {
      for (var at = 0; at < run.length; at += perColumn) {
        final column = run.sublist(at, math.min(run.length, at + perColumn));
        items.add(
          column.length == 1 && perColumn == 1
              ? SpaceRailItem(
                  id: 'event:${column.single.key}',
                  slot: SpaceRailSlot.wide,
                  builder: (context, _) =>
                      _savedEventCard(context, ref, column.single, saved),
                )
              : SpaceRailItem(
                  id: 'events_column:${column.first.key}',
                  slot: SpaceRailSlot.group,
                  widthFor: (m) => m.wide,
                  builder: (context, width) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, s) in column.indexed) ...[
                        if (i > 0) SizedBox(height: estimate.gap),
                        _savedEventCard(context, ref, s, saved),
                      ],
                    ],
                  ),
                ),
        );
      }
      run = <SpaceShortcut>[];
    }

    for (final s in saved.shown) {
      final boards = boardsOf[s.key];
      if (boards == null) {
        run.add(s);
        continue;
      }
      closeRun();
      items.add(
        SpaceRailItem(
          id: 'event:${s.key}',
          slot: SpaceRailSlot.group,
          gameSlots: boards.count,
          widthFor: (m) => math.max(
            m.wide,
            boards.count * m.game + (boards.count - 1) * m.gap,
          ),
          builder: (context, width) {
            final scope = SpaceRailScope.maybeOf(context)!;
            final m = scope.metrics;
            // Over its boards the card has no next card to show beside it
            // (the boards peek under it), so it takes the line between the
            // gutters, as the Events tab's card does, and its dates the room.
            final lead = math
                .min(scope.content, kSpaceRailEventWideMax)
                .clamp(m.wide, width);
            return SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpaceRailStickyLead(
                    width: lead,
                    child: _savedEventCard(context, ref, s, saved),
                  ),
                  SizedBox(height: m.gap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < boards.count; i++) ...[
                        if (i > 0) SizedBox(width: m.gap),
                        SpaceRailGameSlot(
                          width: m.game,
                          child: boards.build(context, i, m),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    closeRun();
    return items;
  }

  /// A live event's boards under its card: plates while they are read, a
  /// retry when they did not load, the boards once they have. Null when a
  /// live event has no boards to show.
  _EventBoards? _eventBoards(SpaceShortcut s, _SavedEvents saved) {
    final id = spaceEventIdOf(s);
    if (saved.boardsLoading(id)) {
      return (
        count: kDiscoveryPreviewBoards,
        build: (context, i, m) => SpaceRailSkeleton(
          width: m.game,
          height: m.estimate(SpaceRailSlot.game, labelled: true),
        ),
      );
    }
    if (saved.boardsFailed(id)) {
      return (
        count: 1,
        build: (context, i, m) =>
            _Retry(onRetry: () => saved.retry(ref, id), stacked: true),
      );
    }
    final games = saved.gamesOf(id);
    if (games.isEmpty) return null;
    final model = saved.modelOf(s);
    final name = discoveryShortEventName(model.title) ?? model.title;
    Widget label(int _) => DiscoveryCardMeta(
      parts: [DiscoveryMetaPart.text(name)],
      semanticsLabel: '${model.title}, live',
    );
    final batch = _batchFor(games, 'my_space:event:$id', shown: games.length);
    return (
      count: games.length,
      build: (context, i, m) => DiscoveryGameCard(
        key: ValueKey<String>('space_event_board_${id}_${games[i].gameId}'),
        games: games,
        index: i,
        labelFor: label,
        rowLabelFor: label,
        liveBatchKeyFor: batch,
      ),
    );
  }
}

/// A live event's boards in the Events rail: how many, and each one at its
/// index in a rail of the given widths.
typedef _EventBoards = ({
  int count,
  Widget Function(BuildContext context, int index, SpaceRailMetrics m) build,
});

/// See all's Events: every saved event's card with, under a live one, its
/// current boards in the viewer's games view.
class _EventsBody extends ConsumerWidget {
  const _EventsBody({required this.items});

  final List<SpaceShortcut> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One read for every saved broadcast, so a reorder never refetches.
    final saved = _SavedEvents(ref, items);
    final mode = ref.watch(gamesListViewModeProvider);

    Widget item(SpaceShortcut s) {
      final card = _savedEventCard(context, ref, s, saved);
      if (!saved.isLive(s)) return card;
      final id = spaceEventIdOf(s);
      final Widget under;
      if (saved.boardsLoading(id)) {
        under = const DiscoveryGameListSkeleton(
          count: kDiscoveryPreviewCards,
          boardCount: kDiscoveryPreviewBoards,
          padded: false,
        );
      } else if (saved.boardsFailed(id)) {
        under = _Retry(onRetry: () => saved.retry(ref, id));
      } else {
        final games = saved.gamesOf(id);
        if (games.isEmpty) return card;
        under = DiscoveryGameList(
          key: ValueKey<String>('space_event_games_$id'),
          games: games,
          limit: kDiscoveryPreviewCards,
          boardLimit: kDiscoveryPreviewBoards,
          padded: false,
          liveBatchKeyFor: _batchFor(
            games,
            'my_space:event:$id',
            shown: _previewCount(mode, games.length),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          SizedBox(height: _itemGap),
          under,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _spaced([for (final s in saved.shown) item(s)]),
    );
  }
}

/// Between the items of a See all list.
double get _itemGap => 12.sp;

List<Widget> _spaced(List<Widget> items) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) SizedBox(height: _itemGap),
    items[i],
  ],
];

/// Today's words for boards that did not load, with a retry. [stacked] sets
/// the words over the action, for a rail slot a game card wide.
class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry, this.stacked = false});

  final VoidCallback onRetry;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final words = Text(
      'Could not load games',
      maxLines: stacked ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: discoveryType(
        context,
        DiscoveryType.label,
        color: context.colors.textSecondary,
      ),
    );
    final action = DiscoveryAction(label: 'Retry', onTap: onRetry);
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 12.sp),
          words,
          action,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: words),
        SizedBox(width: 12.w),
        action,
      ],
    );
  }
}

/// "Sinquefield Cup 2026 · LIVE" under a saved round.
class _RoundMeta extends ConsumerWidget {
  const _RoundMeta({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(
      liveRoundsIdProvider.select(
        (v) => v.valueOrNull?.contains(shortcut.targetId) ?? false,
      ),
    );
    final event =
        (shortcut.params['eventName'] as String?)?.trim() ??
        shortcut.subtitle?.trim() ??
        'Round';
    final style = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimaryMuted,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: event),
          if (live) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: 'LIVE',
              style: TextStyle(
                color: context.colors.accentText,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

// ------------------------------------------------------------------ players

/// The games in progress of the players shown, and where each stands: the
/// players' faces read LIVE for any of them; the games themselves follow
/// the face of the first player shown at their board, left out when a saved
/// live event already draws them.
typedef _PlayersLive = ({
  Set<int> atBoard,
  Map<int, List<GamesTourModel>> after,
  List<GamesTourModel> games,
});

_PlayersLive _playersLive(
  List<SpacePlayerEntry> shown,
  List<GamesTourModel> live, {
  Set<String> drawn = const {},
  bool settled = true,
}) {
  final place = <int, int>{};
  for (final (i, e) in shown.indexed) {
    if (e.fideId case final id?) place.putIfAbsent(id, () => i);
  }
  final seen = <String>{};
  final atBoard = <int>{};
  final after = <int, List<GamesTourModel>>{};
  for (final g in live) {
    if (!seen.add(g.gameId)) continue;
    final ids = [
      for (final id in [g.whitePlayer.fideId, g.blackPlayer.fideId])
        if (id != null && place.containsKey(id)) id,
    ];
    if (ids.isEmpty) continue;
    atBoard.addAll(ids);
    // Until the saved events' boards have settled nothing is drawn here, so
    // a game never appears and then leaves.
    if (!settled || drawn.contains(g.gameId)) continue;
    final at = ids.map((id) => place[id]!).reduce(math.min);
    (after[at] ??= <GamesTourModel>[]).add(g);
  }
  final order = after.keys.toList()..sort();
  return (
    atBoard: atBoard,
    after: after,
    games: [for (final at in order) ...after[at]!],
  );
}

/// Why a live game stands in the Players group, over the game: "Carlsen &
/// Gukesh · playing now". The words that say why never give way to the
/// names: where both names and the words do not fit the card (a grid card
/// on a phone), the line names the first player shown ("Carlsen · playing
/// now"), and where even that does not fit, it says "Playing now" alone
/// (the card itself names both players). Its label is always the whole
/// sentence.
Widget _playingLabel(GamesTourModel g, List<SpacePlayerEntry> shown) {
  final names = <int, String>{};
  for (final e in shown) {
    final id = e.fideId;
    if (id == null) continue;
    names.putIfAbsent(id, () => spaceSurname(_playerName(e.shortcut)));
  }
  final who = [
    for (final id in [g.whitePlayer.fideId, g.blackPlayer.fideId])
      if (id != null && names[id] != null) names[id]!,
  ];
  final semantics = '${who.join(' and ')} playing now'.trim();
  const words = 'playing now';
  if (who.isEmpty) {
    return DiscoveryCardMeta(
      parts: const [DiscoveryMetaPart.text('Playing now')],
      semanticsLabel: semantics,
    );
  }
  return LayoutBuilder(
    builder: (context, constraints) {
      final room = constraints.maxWidth;
      String? fits;
      for (final name in [who.join(' & '), if (who.length > 1) who.first]) {
        if (!room.isFinite || _metaWidth(context, name, words) <= room) {
          fits = name;
          break;
        }
      }
      return DiscoveryCardMeta(
        parts: fits == null
            ? const [DiscoveryMetaPart.text('Playing now')]
            : [
                DiscoveryMetaPart.figure(fits),
                const DiscoveryMetaPart.text(words),
              ],
        semanticsLabel: semantics,
      );
    },
  );
}

/// The width of a card's meta line reading "[figure] · [words]", set as
/// [DiscoveryCardMeta] sets it.
double _metaWidth(BuildContext context, String figure, String words) {
  final base = DefaultTextStyle.of(
    context,
  ).style.merge(discoveryType(context, DiscoveryType.meta));
  final strong = discoveryType(
    context,
    DiscoveryType.meta,
    tabular: true,
  ).copyWith(fontWeight: FontWeight.w700);
  final painter = TextPainter(
    text: TextSpan(
      style: base,
      children: [
        TextSpan(text: figure, style: strong),
        TextSpan(text: ' · $words'),
      ],
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

String _playerName(SpaceShortcut s) {
  final raw = s.params['playerName'];
  return raw is String && raw.trim().isNotEmpty ? raw : s.title;
}

/// One face of My Space's Players: opens the player and records the visit,
/// and its hold menu takes the player out of My Space (a follow stays).
Widget _playerFace(
  BuildContext context,
  WidgetRef ref,
  SpacePlayerEntry e, {
  required bool live,
  double? width,
}) {
  return SpacePlayerFace(
    key: ValueKey<String>('space_player_${e.shortcut.key}'),
    shortcut: e.shortcut,
    width: width,
    live: live,
    onOpen: () => spaceOpenPlayer(context, ref, e),
    menuAction: (menuContext) =>
        spaceRemovePlayerAction(context: menuContext, ref: ref, entry: e),
  );
}

/// The Players group: the players the user follows and the ones they
/// pinned, as one rail of faces, the most recently visited first, sixteen
/// a page (a page's photos asked for together); under it, the games the
/// shown players are playing as a rail of the viewer's game cards, in the
/// faces' order (a game a saved live event already draws is left out).
class _PlayersRail extends ConsumerStatefulWidget {
  const _PlayersRail({required this.gutter});

  final double gutter;

  @override
  ConsumerState<_PlayersRail> createState() => _PlayersRailState();
}

class _PlayersRailState extends ConsumerState<_PlayersRail>
    with SpaceRailPaging {
  @override
  String get pagingId => 'players';

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(spacePlayersProvider) ?? const [];
    const size = kSpacePlayersRailPage;
    final shown = entries.take(pages * size).toList();

    // One read a page: its players' games in progress, and its photos
    // asked for together (each face shows its own as soon as it lands).
    final live = <GamesTourModel>[];
    for (var at = 0; at < shown.length; at += size) {
      final page = shown.sublist(at, math.min(shown.length, at + size));
      final fides = [
        for (final e in page)
          if (e.fideId case final id?) id,
      ];
      if (fides.isEmpty) continue;
      final ids = SpaceIds([for (final id in fides) '$id']);
      ref.watch(spacePlayerPhotosProvider(ids));
      live.addAll(
        ref.watch(spacePlayersLiveGamesProvider(ids)).valueOrNull ??
            const <GamesTourModel>[],
      );
    }

    // A game already drawn under a saved live event is not drawn twice: the
    // Events rail's loaded pages, read through the same provider keys.
    final groups = ref.watch(spaceDatabaseGroupsProvider) ?? const [];
    final events = [
      for (final g in groups)
        if (g.section == SpaceSection.events) ...g.items,
    ];
    final saved = events.isEmpty
        ? null
        : _SavedEvents(
            ref,
            events,
            pages: ref.watch(spaceRailPagesProvider('events')),
          );
    final playing = _playersLive(
      shown,
      live,
      drawn: saved?.drawnGameIds ?? const {},
      settled: saved?.boardsSettled ?? true,
    );
    final games = playing.games;
    final batch = _batchFor(games, 'my_space:players', shown: games.length);

    final faces = [
      for (final e in shown)
        SpaceRailItem(
          id: 'face:${e.identity}',
          slot: SpaceRailSlot.face,
          builder: (context, width) => _playerFace(
            context,
            ref,
            e,
            width: width,
            live: e.fideId != null && playing.atBoard.contains(e.fideId),
          ),
        ),
    ];
    final boards = [
      for (final (i, g) in games.indexed)
        SpaceRailItem(
          id: 'player_board:${g.gameId}',
          slot: SpaceRailSlot.game,
          builder: (context, _) => DiscoveryGameCard(
            key: ValueKey<String>('space_player_board_${g.gameId}'),
            games: games,
            index: i,
            labelFor: (_) => _playingLabel(g, shown),
            rowLabelFor: (_) => _playingLabel(g, shown),
            liveBatchKeyFor: batch,
          ),
        ),
    ];
    return _withLiveRail(
      SpaceRail(
        storageId: 'players',
        items: faces,
        gutter: widget.gutter,
        faces: shown.length,
        hasMore: shown.length < entries.length,
        trailingSlot: SpaceRailSlot.face,
        onLoadMore: loadMore,
      ),
      boards.isEmpty
          ? null
          : SpaceRail(
              key: const ValueKey<String>('space_players_live_rail'),
              storageId: 'players_live',
              items: boards,
              gutter: widget.gutter,
              labelledGames: true,
              airTop: _liveRailAirTop,
            ),
    );
  }
}

/// See all's Players: every face, in rows of whole faces, the same order
/// and hold menu as the rail, and under them the games they are playing.
class _PlayersPage extends ConsumerWidget {
  const _PlayersPage({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(spacePlayersProvider) ?? const [];
    final fides = [
      for (final e in entries)
        if (e.fideId case final id?) '$id',
    ];
    final live = fides.isEmpty
        ? const <GamesTourModel>[]
        : ref
                  .watch(spacePlayersLiveGamesProvider(SpaceIds(fides)))
                  .valueOrNull ??
              const <GamesTourModel>[];
    final playing = _playersLive(entries, live);
    final games = playing.games;
    final byKey = {for (final e in entries) e.shortcut.key: e};
    Widget label(int i) => _playingLabel(games[i], entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SpacePlayerStrip(
          players: [for (final e in entries) e.shortcut],
          liveFideIds: playing.atBoard,
          padding: gutter,
          wrap: true,
          faceBuilder: (s, width, isLive) {
            final e = byKey[s.key];
            if (e == null) {
              return SpacePlayerFace(shortcut: s, width: width, live: isLive);
            }
            return _playerFace(context, ref, e, width: width, live: isLive);
          },
        ),
        if (games.isNotEmpty) ...[
          SizedBox(height: 16.sp),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: DiscoveryGameList(
              key: const ValueKey<String>('space_players_live'),
              games: games,
              padded: false,
              labelFor: label,
              rowLabelFor: label,
              liveBatchKeyFor: _batchFor(
                games,
                'my_space:players',
                shown: games.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ games

/// The saved games of [items] a page at a time, as game cards, and how to
/// open one: [ready] holds the pages whose games have all been looked up;
/// a page still being looked up is [loading].
({
  List<
    ({
      SpaceShortcut pin,
      ({GamesTourModel game, SpaceGamePlayers players}) face,
    })
  >
  ready,
  bool loading,
})
_gamePages(WidgetRef ref, List<SpaceShortcut> items, {required int pages}) {
  final asked = items.take(pages * kSpaceRailPage).toList();
  final faces = [
    for (final s in asked) (pin: s, face: watchSpaceGameFace(ref, s)),
  ];
  var ready = 0;
  var loading = false;
  for (var at = 0; at < faces.length; at += kSpaceRailPage) {
    final page = faces.skip(at).take(kSpaceRailPage);
    if (page.any((f) => f.face.players == SpaceGamePlayers.loading)) {
      loading = true;
      break;
    }
    ready += page.length;
  }
  return (ready: faces.take(ready).toList(), loading: loading);
}

/// The Games rail: every saved game as the viewer's game card, opening on
/// the whole row (previous/next walks the saved games). A game that could
/// not be found keeps its saved names and opens its pin. Ten a page.
class _GamesRail extends ConsumerStatefulWidget {
  const _GamesRail({required this.items, required this.gutter});

  final List<SpaceShortcut> items;
  final double gutter;

  @override
  ConsumerState<_GamesRail> createState() => _GamesRailState();
}

class _GamesRailState extends ConsumerState<_GamesRail> with SpaceRailPaging {
  @override
  String get pagingId => 'games';

  @override
  Widget build(BuildContext context) {
    final paged = _gamePages(ref, widget.items, pages: pages);
    final shown = paged.ready;
    final games = [for (final f in shown) f.face.game];

    void open(List<GamesTourModel> list, int index) {
      if (index < 0 || index >= shown.length) return;
      final pin = shown[index].pin;
      // A liked or library copy opens the user's own analysis; a game that
      // was not found opens its pin, which says so.
      if (pin.params['analysisId'] != null ||
          shown[index].face.players == SpaceGamePlayers.missing) {
        openSpaceShortcut(context, ref, pin);
        return;
      }
      openDiscoveryGame(context, ref, list, index);
      markSpaceShortcutOpened(ref, pin);
    }

    final batch = _batchFor(games, 'my_space:games', shown: games.length);
    final rail = shown.isEmpty && paged.loading
        ? [
            // The first page still being looked up: plates of the cards.
            for (var i = 0; i < 3; i++)
              SpaceRailItem(
                id: 'game_loading:$i',
                slot: SpaceRailSlot.game,
                measured: false,
                builder: (context, width) =>
                    SpaceRailSkeleton(width: width, height: double.infinity),
              ),
          ]
        : [
            for (final (i, f) in shown.indexed)
              SpaceRailItem(
                id: 'game:${f.pin.key}',
                slot: SpaceRailSlot.game,
                builder: (context, _) => DiscoveryGameCard(
                  key: ValueKey<String>('space_game_${f.pin.key}'),
                  games: games,
                  index: i,
                  onOpen: open,
                  liveBatchKeyFor: batch,
                ),
              ),
          ];
    return SpaceRail(
      storageId: 'games',
      items: rail,
      gutter: widget.gutter,
      hasMore: shown.isNotEmpty && shown.length < widget.items.length,
      loading: shown.isNotEmpty && paged.loading,
      trailingSlot: SpaceRailSlot.game,
      onLoadMore: loadMore,
    );
  }
}

// ------------------------------------------------------------------ openings

/// The Openings rail: every saved line on its board, as the viewer's game
/// card lays a position out. Ten a page.
class _OpeningsRail extends ConsumerStatefulWidget {
  const _OpeningsRail({required this.items, required this.gutter});

  final List<SpaceShortcut> items;
  final double gutter;

  @override
  ConsumerState<_OpeningsRail> createState() => _OpeningsRailState();
}

class _OpeningsRailState extends ConsumerState<_OpeningsRail>
    with SpaceRailPaging {
  @override
  String get pagingId => 'openings';

  @override
  Widget build(BuildContext context) {
    final shown = widget.items.take(pages * kSpaceRailPage).toList();
    return SpaceRail(
      storageId: 'openings',
      items: [
        for (final s in shown)
          SpaceRailItem(
            id: 'opening:${s.key}',
            slot: SpaceRailSlot.game,
            builder: (context, _) => SpaceOpeningCard(
              key: ValueKey<String>('space_opening_${s.key}'),
              shortcut: s,
            ),
          ),
      ],
      gutter: widget.gutter,
      hasMore: shown.length < widget.items.length,
      trailingSlot: SpaceRailSlot.game,
      onLoadMore: loadMore,
    );
  }
}

/// See all's openings, a row at a time: one card each, two to a row in
/// grid view.
class _OpeningsBody extends ConsumerWidget {
  const _OpeningsBody({required this.shown});

  final List<SpaceShortcut> shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(gamesListViewModeProvider);
    Widget card(SpaceShortcut s) => SpaceOpeningCard(
      key: ValueKey<String>('space_opening_${s.key}'),
      shortcut: s,
    );
    final rows = <Widget>[];
    if (mode == GamesListViewMode.chessBoardGrid) {
      for (var i = 0; i < shown.length; i += 2) {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: card(shown[i])),
              SizedBox(width: _itemGap),
              Expanded(
                child: i + 1 < shown.length
                    ? card(shown[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      }
    } else {
      rows.addAll([for (final s in shown) card(s)]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _spaced(rows),
    );
  }
}

// ------------------------------------------------------------------ rows

/// A saved database or link as its row, with a live second line (a
/// database's count) and the database's own hold actions.
Widget _savedRow(
  WidgetRef ref,
  SpaceShortcut s, {
  required bool library,
  required List<LibraryFolder> folders,
}) {
  if (!library) {
    final host = Uri.tryParse(s.targetId)?.host;
    return SpaceSavedRow(
      shortcut: s,
      meta: host == null || host.isEmpty ? null : Text(host),
    );
  }
  LibraryFolder? folder;
  if (s.kind == SpaceShortcutKind.miniatures) {
    folder = kMiniaturesFolder;
  } else {
    for (final f in folders) {
      if (f.id == s.targetId) folder = f;
    }
  }
  final found = folder;
  return SpaceSavedRow(
    shortcut: s,
    meta: found == null ? null : SpaceLibraryCountText(folder: found),
    menuActions: found == null
        ? null
        : (menuContext) => spaceLibraryFolderActions(menuContext, ref, found),
  );
}

/// The Databases and Shortcuts rails: one row each. Ten a page.
class _RowsRail extends ConsumerStatefulWidget {
  const _RowsRail({
    required this.items,
    required this.gutter,
    this.library = false,
  });

  final List<SpaceShortcut> items;
  final double gutter;
  final bool library;

  @override
  ConsumerState<_RowsRail> createState() => _RowsRailState();
}

class _RowsRailState extends ConsumerState<_RowsRail> with SpaceRailPaging {
  @override
  String get pagingId => widget.library ? 'library' : 'links';

  @override
  Widget build(BuildContext context) {
    final folders = widget.library
        ? ref.watch(spaceLibraryFoldersProvider).folders
        : const <LibraryFolder>[];
    final shown = widget.items.take(pages * kSpaceRailPage).toList();
    return SpaceRail(
      storageId: pagingId,
      items: [
        for (final s in shown)
          SpaceRailItem(
            id: 'row:${s.key}',
            slot: SpaceRailSlot.wide,
            builder: (context, _) =>
                _savedRow(ref, s, library: widget.library, folders: folders),
          ),
      ],
      gutter: widget.gutter,
      hasMore: shown.length < widget.items.length,
      trailingSlot: SpaceRailSlot.wide,
      onLoadMore: loadMore,
    );
  }
}

/// See all's rows: one each.
class _RowsBody extends ConsumerWidget {
  const _RowsBody({required this.shown, this.library = false});

  final List<SpaceShortcut> shown;
  final bool library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = library
        ? ref.watch(spaceLibraryFoldersProvider).folders
        : const <LibraryFolder>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _spaced([
        for (final s in shown)
          _savedRow(ref, s, library: library, folders: folders),
      ]),
    );
  }
}

// ------------------------------------------------------------------ smart

class _SmartEventsBody extends StatelessWidget {
  const _SmartEventsBody({required this.shown});

  final List<SpaceShortcut> shown;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _spaced([for (final s in shown) _SavedSmartEvent(shortcut: s)]),
    );
  }
}

class _SavedSmartEvent extends ConsumerWidget {
  const _SavedSmartEvent({required this.shortcut});

  final SpaceShortcut shortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = smartEventRequestFromSpaceShortcut(shortcut);
    if (saved == null) return SpaceSavedRow(shortcut: shortcut);
    // Today's broadcasts, read once for every Smart Event card and filtered
    // per card in memory.
    final members = ref
        .watch(discoverySmartEventMembersProvider(saved.criteria))
        .valueOrNull;
    final request = members == null ? saved : saved.withEvents(members);
    final events = request.events;
    final elos = [
      for (final e in events)
        if (e.maxAvgElo > 0) e.maxAvgElo,
    ];
    final avg = elos.isEmpty
        ? 0
        : (elos.reduce((a, b) => a + b) / elos.length).round();
    return SmartEventCard(
      key: ValueKey<String>('space_smart_${shortcut.key}'),
      quiet: true,
      tierLabel: request.tierLabel,
      minElo: request.minElo,
      liveCount: events.length,
      avgElo: avg,
      titleSuffix: request.titleSuffix,
      caption: request.caption,
      countSingular: request.countSingular,
      countPlural: request.countPlural,
      formatsAndStates: request.formatsAndStates,
      summary: smartEventCardSummary(request),
      live: watchSmartEventLive(ref, request),
      spaceDraft: smartEventSpaceDraft(request),
      onTap: () => openSpaceShortcut(context, ref, shortcut),
    );
  }
}

// ------------------------------------------------------------------ see all

/// Every saved thing of one My Space group, for its See all page, as a
/// vertical list of the same cards the rail draws: event cards with their
/// live boards, the faces (in rows of whole faces) with their games, the
/// games and lines in the viewer's games view, the rows, the smart events.
/// Games and lines are built a row at a time as they scroll in.
class SpaceGroupPage extends ConsumerWidget {
  const SpaceGroupPage({super.key, required this.section});

  final SpaceSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(spaceDatabaseGroupsProvider);
    if (groups == null) return const SizedBox.shrink();
    final items = [
      for (final g in groups)
        if (g.section == section) ...g.items,
    ];
    final title = spaceGroupTitle(section);
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Nothing in $title yet',
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }
    final gutter = hubGutter;
    final mode = ref.watch(gamesListViewModeProvider);
    final per = mode == GamesListViewMode.chessBoardGrid ? 2 : 1;

    // Each block is one lazily built item of the page; [edge] blocks set
    // their own gutter (the faces).
    final blocks = <({Widget Function() build, bool edge})>[];
    void add(Widget Function() build, {bool edge = false}) =>
        blocks.add((build: build, edge: edge));

    switch (section) {
      case SpaceSection.events:
        add(() => _EventsBody(items: items));
      case SpaceSection.players:
        add(() => _PlayersPage(gutter: gutter), edge: true);
      case SpaceSection.games:
        final faces = [
          for (final s in items) (pin: s, face: watchSpaceGameFace(ref, s)),
        ];
        final ready = [
          for (final f in faces)
            if (f.face.players == SpaceGamePlayers.ready) f,
        ];
        final games = [for (final f in ready) f.face.game];
        void open(List<GamesTourModel> list, int index) {
          if (index < 0 || index >= ready.length) return;
          final pin = ready[index].pin;
          if (pin.params['analysisId'] != null) {
            openSpaceShortcut(context, ref, pin);
            return;
          }
          openDiscoveryGame(context, ref, list, index);
          markSpaceShortcutOpened(ref, pin);
        }

        for (var at = 0; at < games.length; at += per) {
          final start = at;
          add(
            () => DiscoveryGameList(
              key: ValueKey<String>('space_all_games_$start'),
              games: games,
              start: start,
              limit: per,
              boardLimit: per,
              padded: false,
              onOpen: open,
              liveBatchKeyFor: _batchFor(
                games,
                'my_space:games:$start',
                start: start,
                shown: per,
              ),
            ),
          );
        }
        if (faces.any((f) => f.face.players == SpaceGamePlayers.loading)) {
          add(
            () => const DiscoveryGameListSkeleton(
              count: kDiscoveryPreviewCards,
              boardCount: kDiscoveryPreviewBoards,
              padded: false,
            ),
          );
        }
        for (final f in faces) {
          if (f.face.players == SpaceGamePlayers.missing) {
            add(() => SpaceSavedRow(shortcut: f.pin));
          }
        }
      case SpaceSection.openings:
        for (var at = 0; at < items.length; at += per) {
          final row = items.sublist(at, math.min(items.length, at + per));
          add(() => _OpeningsBody(shown: row));
        }
      case SpaceSection.library:
      case SpaceSection.links:
        for (final s in items) {
          add(
            () =>
                _RowsBody(shown: [s], library: section == SpaceSection.library),
          );
        }
      case SpaceSection.smartEvents:
        for (final s in items) {
          add(() => _SavedSmartEvent(shortcut: s));
        }
      case SpaceSection.likes:
        break;
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: 8.sp,
        bottom: 32.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: blocks.length,
      itemBuilder: (context, i) {
        final block = blocks[i];
        return Padding(
          padding: EdgeInsets.fromLTRB(
            block.edge ? 0 : gutter,
            i == 0 ? 0 : _itemGap,
            block.edge ? 0 : gutter,
            0,
          ),
          child: block.build(),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ toggle

/// Saves a suggested thing to My Space in one tap, or takes it back: the
/// app's own Add to My Space glyph, bare, filled once saved. A 44 target;
/// the glyph gives under the finger on a spring.
class SpaceSaveToggle extends ConsumerStatefulWidget {
  const SpaceSaveToggle({super.key, required this.draft});

  final SpaceShortcut draft;

  @override
  ConsumerState<SpaceSaveToggle> createState() => _SpaceSaveToggleState();
}

class _SpaceSaveToggleState extends ConsumerState<SpaceSaveToggle> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(spaceShortcutExistsProvider(widget.draft.key));
    final reduce = MediaQuery.disableAnimationsOf(context);
    final label = saved
        ? 'Remove ${widget.draft.title} from My Space'
        : 'Add ${widget.draft.title} to My Space';
    void toggle() =>
        toggleSpaceShortcut(context: context, ref: ref, draft: widget.draft);
    return Semantics(
      button: true,
      toggled: saved,
      label: label,
      excludeSemantics: true,
      onTap: toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: toggle,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: SingleMotionBuilder(
              motion: const CupertinoMotion.snappy(),
              value: _pressed && !reduce ? 0.85 : 1.0,
              builder: (context, value, child) => Transform.scale(
                scale: (value - 1).abs() < 0.001 ? 1.0 : value,
                child: child,
              ),
              child: Icon(
                saved
                    ? Icons.dashboard_customize
                    : Icons.dashboard_customize_outlined,
                size: 22.ic,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ row

/// A saved database, round or link as a row in the Events card language:
/// the card surface, a plate where an event keeps its photo (here the
/// thing's pixel object), its name and a second line ([meta], else what it
/// is). People never take this row: a saved player is a face.
class SpaceSavedRow extends ConsumerWidget {
  const SpaceSavedRow({
    super.key,
    required this.shortcut,
    this.meta,
    this.menuActions,
  });

  final SpaceShortcut shortcut;

  /// The second line, live (a database's count); the saved kind and
  /// subtitle when null.
  final Widget? meta;

  /// The thing's own long-press actions, before Open and My Space.
  final List<LibraryMenuAction> Function(BuildContext context)? menuActions;

  /// What the row says the thing is, when the saved subtitle does not.
  static String kindLabel(SpaceShortcutKind kind) => switch (kind) {
    SpaceShortcutKind.player => 'Player',
    SpaceShortcutKind.playerGames => 'Player games',
    SpaceShortcutKind.playerOpenings => 'Player openings',
    SpaceShortcutKind.event => 'Event',
    SpaceShortcutKind.round => 'Round',
    SpaceShortcutKind.game => 'Game',
    SpaceShortcutKind.position => 'Position',
    SpaceShortcutKind.opening => 'Opening',
    SpaceShortcutKind.folder => 'Database',
    SpaceShortcutKind.smartEvent => 'Smart Event',
    SpaceShortcutKind.countrymen => 'Countrymen',
    SpaceShortcutKind.miniatures => 'Miniatures',
    SpaceShortcutKind.likes => 'Liked games',
    SpaceShortcutKind.streak => 'Streak',
    SpaceShortcutKind.link => 'Link',
    SpaceShortcutKind.collection => 'Collection',
  };

  /// The pixel object standing for the thing, from My Space's own set.
  static SpaceSection artFor(SpaceShortcutKind kind) => switch (kind) {
    SpaceShortcutKind.folder ||
    SpaceShortcutKind.miniatures ||
    SpaceShortcutKind.collection => SpaceSection.library,
    SpaceShortcutKind.position ||
    SpaceShortcutKind.opening ||
    SpaceShortcutKind.playerOpenings => SpaceSection.openings,
    SpaceShortcutKind.event || SpaceShortcutKind.round => SpaceSection.events,
    SpaceShortcutKind.game => SpaceSection.games,
    SpaceShortcutKind.smartEvent => SpaceSection.smartEvents,
    SpaceShortcutKind.likes => SpaceSection.likes,
    SpaceShortcutKind.player ||
    SpaceShortcutKind.playerGames ||
    SpaceShortcutKind.countrymen ||
    SpaceShortcutKind.streak => SpaceSection.players,
    SpaceShortcutKind.link => SpaceSection.links,
  };

  /// The saved second line: "Database · 212 games", or the kind alone.
  static String savedMeta(SpaceShortcut s) {
    final subtitle = s.subtitle?.trim();
    final kind = kindLabel(s.kind);
    return subtitle == null || subtitle.isEmpty || subtitle == kind
        ? kind
        : '$kind · $subtitle';
  }

  void _open(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();
    openSpaceShortcut(context, ref, shortcut);
  }

  /// The thing's pixel object; a collection's own cover when it has one.
  Widget _plate(BuildContext context, double width) {
    final art = SpacePlateArt(section: artFor(shortcut.kind));
    final cover = shortcut.params['coverUrl'];
    if (shortcut.kind != SpaceShortcutKind.collection ||
        cover is! String ||
        cover.trim().isEmpty) {
      return art;
    }
    return CachedNetworkImage(
      imageUrl: cover,
      fit: BoxFit.cover,
      memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => art,
      errorWidget: (_, _, _) => art,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final saved = savedMeta(shortcut);
    final plateWidth = 108.w;
    final plateHeight = plateWidth * 4 / 5;
    final metaStyle = AppTypography.textXsMedium.copyWith(
      color: colors.textPrimaryMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: isLight
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      padding: EdgeInsets.all(6.sp),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6.br),
            child: ColoredBox(
              color: isLight ? colors.surfaceRecessed : kHubTileInk,
              child: SizedBox(
                width: plateWidth,
                height: plateHeight,
                child: _plate(context, plateWidth),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shortcut.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                    fontSize: 14.f,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 4.h),
                DefaultTextStyle.merge(
                  style: metaStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child:
                      meta ??
                      Text(saved, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          SizedBox(width: 4.w),
          Icon(
            Icons.chevron_right_rounded,
            size: 20.ic,
            color: colors.iconSecondary,
          ),
          SizedBox(width: 4.w),
        ],
      ),
    );

    final own = menuActions;
    return Semantics(
      button: true,
      label: '${shortcut.title}, $saved',
      excludeSemantics: true,
      onTap: () => _open(context, ref),
      child: TappableScale(
        onTap: () => _open(context, ref),
        child: CardContextMenu(
          onPreviewTap: () => _open(context, ref),
          actions: (menuContext) => [
            LibraryMenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onSelected: () => _open(context, ref),
            ),
            ...?own?.call(menuContext),
            spaceMenuAction(context: menuContext, ref: ref, draft: shortcut),
          ],
          child: card,
        ),
      ),
    );
  }
}

/// A pixel object centred on a row's plate (never a person's: people get
/// their faces).
class SpacePlateArt extends StatelessWidget {
  const SpacePlateArt({super.key, required this.section});

  final SpaceSection section;

  @override
  Widget build(BuildContext context) {
    final tone = PixelTone.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        return PixelArtView(
          scene: PixelScene.inBox(
            PixelArt.door(section, tone: tone),
            size,
            spacePlateArtBox(size),
          ),
        );
      },
    );
  }
}

/// Where a pixel object sits on a card's plate: centred, small enough that
/// the plate reads as a frame around it rather than a crop of it.
Rect spacePlateArtBox(Size size) => Rect.fromCenter(
  center: size.center(Offset.zero),
  width: size.width * 0.52,
  height: size.height * 0.62,
);
