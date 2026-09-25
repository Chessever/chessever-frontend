import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
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
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_game_card_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_opening_card.dart';
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart';
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

/// One group of My Database: the saved things of one type, in the order
/// the user keeps them.
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

/// How many of a group show on My Space before "See all" takes over. Games
/// show half as many in board view, where a card is a whole screen wide.
int spaceGroupCap(SpaceSection section, {GamesListViewMode? mode}) =>
    switch (section) {
      SpaceSection.events => 3,
      SpaceSection.players => 8,
      SpaceSection.games || SpaceSection.openings =>
        mode == GamesListViewMode.chessBoard
            ? kDiscoveryPreviewBoards
            : kDiscoveryPreviewCards,
      SpaceSection.library => 3,
      SpaceSection.links => 3,
      SpaceSection.smartEvents => 2,
      SpaceSection.likes => 0,
    };

/// Whether a saved thing belongs on My Database: My Likes has its own tile,
/// and streak cards stay out while streaks are hidden.
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

/// [list] (in store order) as My Database's groups: typed, in
/// [kSpaceDatabaseOrder], empty ones left out. Events whose key is in
/// [liveFirst] lead their group, each class keeping store order.
List<SpaceDatabaseGroup> spaceDatabaseGroups(
  List<SpaceShortcut> list, {
  Set<String> liveFirst = const {},
}) {
  final bySection = <SpaceSection, List<SpaceShortcut>>{};
  for (final s in list) {
    if (!spaceShowsInDatabase(s)) continue;
    (bySection[s.section] ??= <SpaceShortcut>[]).add(s);
  }
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

/// What My Database shows: the saved things in their groups. Null until the
/// saved list has loaded; a list that failed to load reads as empty.
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
      return spaceDatabaseGroups(list, liveFirst: liveFirst);
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

/// One group of My Database: its quiet sub-header (type, count, See all
/// while some are hidden) over its items, each drawn with the card the rest
/// of the app gives that kind of thing. [gutter] is the page's side inset;
/// a sideways row of faces runs past it to the screen edge.
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
    final mode = ref.watch(gamesListViewModeProvider);
    final cap = spaceGroupCap(section, mode: mode);
    final hidden = items.length > cap;

    void seeAll() {
      HapticFeedbackService.navigation();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SpaceSectionScreen(section: section, pinsOnly: true),
        ),
      );
    }

    Widget pad(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: child,
    );

    final shown = items.take(cap).toList();
    final List<Widget> body = switch (section) {
      SpaceSection.events => [pad(_EventsBody(items: items))],
      SpaceSection.players => [
        _PlayersBody(items: items, shown: shown, gutter: gutter),
      ],
      SpaceSection.games => [pad(_GamesBody(items: items))],
      SpaceSection.openings => [pad(_OpeningsBody(shown: shown))],
      SpaceSection.library => [pad(_RowsBody(shown: shown, library: true))],
      SpaceSection.links => [pad(_RowsBody(shown: shown))],
      SpaceSection.smartEvents => [pad(_SmartEventsBody(shown: shown))],
      SpaceSection.likes => const <Widget>[],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        pad(
          SpaceSectionHeader(
            key: ValueKey<String>('space_header_${section.name}'),
            title: spaceGroupTitle(section),
            count: items.length,
            onSeeAll: hidden ? seeAll : null,
          ),
        ),
        ...body,
      ],
    );
  }

}

/// The Players group: the saved players as faces, and under them the games
/// they are playing now that no saved event above already shows, each
/// labelled with who is at the board. [full] is See all: every face (in
/// rows), every game.
class _PlayersBody extends ConsumerWidget {
  const _PlayersBody({
    required this.items,
    required this.shown,
    required this.gutter,
    this.full = false,
  });

  final List<SpaceShortcut> items;
  final List<SpaceShortcut> shown;
  final double gutter;
  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget pad(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: child,
    );
    final mode = ref.watch(gamesListViewModeProvider);
    final pinned = <int>{
      for (final s in items)
        if (s.kind == SpaceShortcutKind.player ||
            s.kind == SpaceShortcutKind.playerGames)
          if (spacePinFideId(s) case final id?) id,
    };
    final live = pinned.isEmpty
        ? const <GamesTourModel>[]
        : ref
                  .watch(
                    spacePlayersLiveGamesProvider(
                      SpaceIds([for (final id in pinned) '$id']),
                    ),
                  )
                  .valueOrNull ??
              const <GamesTourModel>[];
    bool pinnedPlays(GamesTourModel g) =>
        pinned.contains(g.whitePlayer.fideId) ||
        pinned.contains(g.blackPlayer.fideId);
    final atBoard = [
      for (final g in live)
        if (pinnedPlays(g)) g,
    ];
    final liveIds = <int>{
      for (final g in atBoard)
        for (final id in [g.whitePlayer.fideId, g.blackPlayer.fideId])
          if (id != null && pinned.contains(id)) id,
    };

    // A game already drawn under a saved live event is not drawn twice:
    // the Players group shows only what the Events group does not. Until
    // those boards have settled nothing is drawn here, so a game never
    // appears and then leaves.
    final groups = full
        ? const <SpaceDatabaseGroup>[]
        : ref.watch(spaceDatabaseGroupsProvider) ?? const [];
    final events = [
      for (final g in groups)
        if (g.section == SpaceSection.events) ...g.items,
    ];
    final saved = events.isEmpty ? null : _SavedEvents(ref, events);
    final boards = saved?.boards;
    final settled =
        boards == null || boards.hasValue || boards.hasError;
    final drawn = saved?.drawnGameIds(mode) ?? const <String>{};

    // In the strip's order, so the boards read left to right as the faces do.
    final place = <int, int>{};
    final names = <int, String>{};
    for (final (i, s) in items.indexed) {
      final id = spacePinFideId(s);
      if (id == null || s.kind == SpaceShortcutKind.countrymen) continue;
      place.putIfAbsent(id, () => i);
      final raw = s.params['playerName'];
      names.putIfAbsent(
        id,
        () => spaceSurname(raw is String && raw.trim().isNotEmpty ? raw : s.title),
      );
    }
    int placeOf(GamesTourModel g) => [
      for (final id in [g.whitePlayer.fideId, g.blackPlayer.fideId])
        if (id != null && place[id] != null) place[id]!,
    ].fold(items.length, (a, b) => a < b ? a : b);
    final playing = !settled
        ? const <GamesTourModel>[]
        : ([
            for (final g in atBoard)
              if (!drawn.contains(g.gameId)) g,
          ]..sort((a, b) => placeOf(a).compareTo(placeOf(b))));

    Widget label(int i) {
      final g = playing[i];
      final who = [
        for (final id in [g.whitePlayer.fideId, g.blackPlayer.fideId])
          if (id != null && names[id] != null) names[id]!,
      ];
      final name = who.join(' & ');
      return DiscoveryCardMeta(
        parts: [
          if (name.isNotEmpty) DiscoveryMetaPart.figure(name),
          const DiscoveryMetaPart.text('playing now'),
        ],
        semanticsLabel: '${who.join(' and ')} playing now',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
      Padding(
        padding: EdgeInsets.only(bottom: 4.w),
        child: SpacePlayerStrip(
          players: shown,
          liveFideIds: liveIds,
          padding: gutter,
          wrap: full,
        ),
      ),
      if (playing.isNotEmpty) ...[
        SizedBox(height: 12.sp),
        pad(
          DiscoveryGameList(
            key: const ValueKey<String>('space_players_live'),
            games: playing,
            limit: full ? null : kDiscoveryPreviewCards,
            boardLimit: full ? null : kDiscoveryPreviewBoards,
            padded: false,
            labelFor: label,
            rowLabelFor: label,
            liveBatchKeyFor: _batchFor(
              playing,
              'my_space:players',
              shown: full
                  ? playing.length
                  : _previewCount(mode, playing.length),
            ),
          ),
        ),
      ],
      ],
    );
  }
}

/// A live batch over the [shown] games of [games] from [start] (the cards
/// drawn), one channel for them; the games past the preview never
/// subscribe.
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

/// How many of [length] games a preview draws in [mode]: the one rule every
/// section follows.
int _previewCount(GamesListViewMode mode, int length) =>
    DiscoveryGameList.shownFor(
      mode,
      length,
      limit: kDiscoveryPreviewCards,
      boardLimit: kDiscoveryPreviewBoards,
    );

/// What the Events group knows about its saved events: their fresh card
/// models, which of the shown ones are live now, and those events' boards.
/// Read the same way (the same provider keys) by the Events group and by
/// the Players group, which leaves out the boards already drawn here.
class _SavedEvents {
  _SavedEvents(WidgetRef ref, this.items, {bool full = false})
    : shown = full
          ? items
          : items.take(spaceGroupCap(SpaceSection.events)).toList() {
    final ids = SpaceIds([
      for (final s in items)
        if (spaceIsBroadcastEvent(s)) spaceEventIdOf(s),
    ]);
    models = ids.isEmpty
        ? const <String, GroupEventCardModel>{}
        : ref.watch(spaceEventCardModelsProvider(ids));
    _liveIds = {...?ref.watch(liveGroupBroadcastIdsProvider).valueOrNull};
    live = [
      for (final s in shown)
        if (isLive(s)) spaceEventIdOf(s),
    ];
    boards = live.isEmpty
        ? null
        : ref.watch(spaceLiveEventGamesProvider(SpaceIds(live)));
  }

  final List<SpaceShortcut> items;
  final List<SpaceShortcut> shown;
  late final Map<String, GroupEventCardModel> models;
  late final Set<String> _liveIds;
  late final List<String> live;
  late final AsyncValue<SpaceLiveEventGames>? boards;

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

  /// [id]'s boards, when they have loaded.
  List<GamesTourModel> gamesOf(String id) =>
      boards?.valueOrNull?.byEvent[id]?.visibleGames ??
      const <GamesTourModel>[];

  /// The ids of every board drawn under the shown events in [mode].
  Set<String> drawnGameIds(GamesListViewMode mode) => {
    for (final id in live)
      for (final g in gamesOf(id).take(_previewCount(mode, gamesOf(id).length)))
        g.gameId,
  };
}

/// Between the items of a group.
double get _itemGap => 12.sp;

List<Widget> _spaced(List<Widget> items) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) SizedBox(height: _itemGap),
    items[i],
  ],
];

class _EventsBody extends ConsumerWidget {
  const _EventsBody({required this.items, this.full = false});

  final List<SpaceShortcut> items;

  /// Every event, not the group's first few (See all).
  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One read for every saved broadcast in the group, shown or not, so
    // See all and a reorder never refetch.
    final saved = _SavedEvents(ref, items, full: full);
    final boards = saved.boards;
    final live = saved.live;
    final mode = ref.watch(gamesListViewModeProvider);

    Widget item(SpaceShortcut s) {
      if (s.kind == SpaceShortcutKind.round) {
        return SpaceSavedRow(
          shortcut: s,
          meta: _RoundMeta(shortcut: s),
        );
      }
      final card = EventCard(
        key: ValueKey<String>('space_event_${s.key}'),
        tourEventCardModel: saved.modelOf(s),
        heroTagSuffix: '_myspace',
        forceCompactLayout: true,
        onTap: () => openSpaceShortcut(context, ref, s),
      );
      if (!saved.isLive(s) || boards == null) return card;
      final id = spaceEventIdOf(s);
      final Widget under;
      final value = boards.valueOrNull;
      if (value == null) {
        under = boards.hasError
            ? _Retry(onRetry: () => _retry(ref, live))
            : const DiscoveryGameListSkeleton(
                count: kDiscoveryPreviewCards,
                boardCount: kDiscoveryPreviewBoards,
                padded: false,
              );
      } else if (value.failed.contains(id)) {
        under = _Retry(onRetry: () => _retry(ref, live));
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

  static void _retry(WidgetRef ref, List<String> live) {
    HapticFeedbackService.buttonPress();
    ref.invalidate(spaceLiveEventGamesProvider(SpaceIds(live)));
  }
}

/// Today's words for boards that did not load, with a retry.
class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Could not load games',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: discoveryType(
              context,
              DiscoveryType.label,
              color: context.colors.textSecondary,
            ),
          ),
        ),
        SizedBox(width: 12.w),
        DiscoveryAction(label: 'Retry', onTap: onRetry),
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

// ------------------------------------------------------------------ games

class _GamesBody extends ConsumerWidget {
  const _GamesBody({required this.items});

  final List<SpaceShortcut> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(gamesListViewModeProvider);
    final cap = spaceGroupCap(SpaceSection.games, mode: mode);
    // Every saved game resolves through one batched read, so the board
    // walks all of them; the page draws the first few.
    final faces = [
      for (final s in items.take(40))
        (pin: s, face: watchSpaceGameFace(ref, s)),
    ];
    final previewed = faces.take(cap);
    if (previewed.any((f) => f.face.players == SpaceGamePlayers.loading)) {
      return DiscoveryGameListSkeleton(
        count: cap,
        boardCount: spaceGroupCap(
          SpaceSection.games,
          mode: GamesListViewMode.chessBoard,
        ),
        padded: false,
      );
    }
    final ready = [
      for (final f in faces)
        if (f.face.players == SpaceGamePlayers.ready) f,
    ];
    final games = [for (final f in ready) f.face.game];
    final missing = [
      for (final f in previewed)
        if (f.face.players == SpaceGamePlayers.missing) f.pin,
    ];

    void open(List<GamesTourModel> list, int index) {
      if (index < 0 || index >= ready.length) return;
      final pin = ready[index].pin;
      // A liked or library copy opens the user's own analysis.
      if (pin.params['analysisId'] != null) {
        openSpaceShortcut(context, ref, pin);
        return;
      }
      openDiscoveryGame(context, ref, list, index);
      markSpaceShortcutOpened(ref, pin);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _spaced([
        if (games.isNotEmpty)
          DiscoveryGameList(
            key: const ValueKey<String>('space_games'),
            games: games,
            limit: cap - missing.length,
            padded: false,
            onOpen: open,
            liveBatchKeyFor: _batchFor(
              games,
              'my_space:games',
              shown: DiscoveryGameList.shownFor(
                mode,
                games.length,
                limit: cap - missing.length,
              ),
            ),
          ),
        for (final s in missing) SpaceSavedRow(shortcut: s),
      ]),
    );
  }
}

// ------------------------------------------------------------------ openings

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

/// Databases and links: one row each, with a live second line.
class _RowsBody extends ConsumerWidget {
  const _RowsBody({required this.shown, this.library = false});

  final List<SpaceShortcut> shown;
  final bool library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = library
        ? ref.watch(spaceLibraryFoldersProvider).folders
        : const <LibraryFolder>[];
    LibraryFolder? folderOf(SpaceShortcut s) {
      if (s.kind == SpaceShortcutKind.miniatures) return kMiniaturesFolder;
      for (final f in folders) {
        if (f.id == s.targetId) return f;
      }
      return null;
    }

    Widget row(SpaceShortcut s) {
      if (!library) {
        final host = Uri.tryParse(s.targetId)?.host;
        return SpaceSavedRow(
          shortcut: s,
          meta: host == null || host.isEmpty ? null : Text(host),
        );
      }
      final folder = folderOf(s);
      return SpaceSavedRow(
        shortcut: s,
        meta: folder == null ? null : SpaceLibraryCountText(folder: folder),
        menuActions: folder == null
            ? null
            : (menuContext) =>
                  spaceLibraryFolderActions(menuContext, ref, folder),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _spaced([for (final s in shown) row(s)]),
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

/// Every saved thing of one My Database group, for its See all page, drawn
/// exactly as the group draws its first few: event cards with their live
/// boards, the faces (in rows of whole faces) with their games, the games
/// and lines in the viewer's games view, the rows, the smart events. Games
/// and lines are built a row at a time as they scroll in.
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
        add(() => _EventsBody(items: items, full: true));
      case SpaceSection.players:
        add(
          () => _PlayersBody(
            items: items,
            shown: items,
            gutter: gutter,
            full: true,
          ),
          edge: true,
        );
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
            () => _RowsBody(
              shown: [s],
              library: section == SpaceSection.library,
            ),
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
