import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/my_prep_screen.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_game_card_provider.dart'
    show spaceGameCardProvider;
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/screens/my_space/widgets/space_player_strip.dart'
    show SpacePlayerFace;
import 'package:chessever2/screens/my_space/widgets/space_section_header.dart';
import 'package:chessever2/screens/my_space/widgets/space_rail.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_screen.dart';
import 'package:chessever2/screens/my_space/widgets/space_opening_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart'
    show PlayerProfileScreen;
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart'
    show ForYouEventGamesSnapshot;
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart'
    show DiscoveryCardMeta;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoverySmartEventMembersProvider;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_tutorial.dart';
import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart'
    show TutorialStepIndicator;
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/contrast_audit.dart';

/// Store double: seeded in memory, never touches SQLite or Supabase (the real
/// notifier reads its cache in build(), which leaves timers pending in tests).
class _FakeSpaceShortcuts extends SpaceShortcutsNotifier {
  _FakeSpaceShortcuts(this._seed);

  final List<SpaceShortcut> _seed;

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _seed;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft.copyWith(sortIndex: 99), ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in _list) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  /// Back where it stood: the real store's order, by sort index.
  @override
  Future<void> restore(SpaceShortcut item) async {
    if (_list.any((s) => s.key == item.key)) return;
    state = AsyncData(SpaceShortcutsNotifier.inDisplayOrder([item, ..._list]));
  }

  @override
  Future<void> moveToFront(String id) async {}

  @override
  Future<void> moveWithinSection(String key, int toIndex) async {
    final plan = SpaceShortcutsNotifier.planSectionMove(_list, key, toIndex);
    if (plan != null) state = AsyncData(plan.list);
  }

  @override
  Future<void> markOpened(String id) async {}

  /// The keys of [section] in the order the store keeps them.
  List<String> keysOf(SpaceSection section) => [
    for (final s in _list)
      if (s.section == section) s.key,
  ];
}

/// A store whose server answers a removal only once [answer] is called:
/// the list drops the thing at once, the delete stays on the wire. A
/// put-back is in the list at once, and its row is written (into
/// [serverWrites]) once the delete has answered, as the real store does
/// through [SpacePendingDeletes].
class _SlowRemoveStore extends _FakeSpaceShortcuts {
  _SlowRemoveStore(super.seed);

  final _gate = Completer<void>();
  final _deletes = SpacePendingDeletes();

  /// The keys whose put-back row reached the server, in order.
  final List<String> serverWrites = [];

  bool get answered => _gate.isCompleted;

  void answer() => _gate.complete();

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    // The list changes before the first await, as the real store's does.
    final removed = super.removeTarget(kind, targetId);
    await _deletes.run(
      SpaceShortcut.keyFor(kind, targetId),
      () => _gate.future,
    );
    return removed;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    await super.restore(item);
    await _deletes.settled(item.key);
    serverWrites.add(item.key);
  }
}

/// Edit's tips' memory in memory: due until shown or skipped; the Players'
/// tips kept apart, as they leave holding to reorder untaught.
class _Tips extends SpaceEditTutorialStore {
  bool _due = true;
  bool _players = false;
  int shown = 0;
  int playersShownCount = 0;

  @override
  bool due() => _due;

  @override
  bool playersShown() => _players;

  @override
  void markShown() {
    shown++;
    _due = false;
  }

  @override
  void markPlayersShown() {
    playersShownCount++;
    _players = true;
  }

  @override
  void markSkipped() => _due = false;
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Hidden keys in memory (the real one writes device storage).
class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};

  @override
  void hide(String key) => state = {...state, key};

  @override
  void unhide(String key) => state = {...state}..remove(key);
}

/// The followed players, and a tally of every write that would unfollow
/// one (My Space must never make one).
class _Favorites extends FavoritePlayersNotifierNew {
  _Favorites([this.seed = const []]);

  final List<FavoritePlayer> seed;
  int unfollows = 0;

  @override
  Future<List<FavoritePlayer>> build() async => seed;

  @override
  Future<void> removeFavorite(
    String playerName, {
    String? fideId,
    String? memorialSourceIdentity,
  }) async => unfollows++;

  @override
  Future<bool> toggleFavorite({
    String? fideId,
    required String playerName,
    String? countryCode,
    int? rating,
    String? title,
    String? gamebasePlayerId,
    String? memorialSourceIdentity,
    String? memorialRouteId,
  }) async {
    unfollows++;
    return false;
  }
}

/// Visits in memory, seeded.
class _Visits extends SpacePlayerVisits {
  _Visits(this.seed);

  final Map<String, int> seed;

  @override
  Map<String, int> build() => seed;

  @override
  void visit(String identity, {DateTime? at}) => state = {
    ...state,
    identity: (at ?? DateTime.now()).millisecondsSinceEpoch,
  };
}

FavoritePlayer _follow(String name, int fide, int rating, {int day = 1}) =>
    FavoritePlayer(
      id: 'fav-$fide',
      userId: 'u1',
      fideId: '$fide',
      playerName: name,
      metadata: {'title': 'GM', 'rating': rating},
      createdAt: DateTime(2026, 7, day),
      updatedAt: DateTime(2026, 7, day),
    );

class _Feed extends StateNotifier<ForYouState> implements ForYouNotifier {
  _Feed(List<GroupEventCardModel> events)
    : super(ForYouState(events: events, hasMore: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

GroupEventCardModel _event(
  String id,
  String title,
  TourEventCategory category,
) => GroupEventCardModel(
  id: id,
  title: title,
  dates: 'Sep 18 - 29, 2026',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: category,
  timeControl: 'Standard',
  endDate: DateTime(2026, 9, 29),
  startDate: DateTime(2026, 9, 18),
);

final _feed = [
  _event('ev-a', 'Sinquefield Cup 2026', TourEventCategory.live),
  _event('ev-b', 'FIDE Grand Swiss 2026', TourEventCategory.live),
  _event('ev-done', 'Norway Chess 2026', TourEventCategory.completed),
  _event('ev-c', 'Chennai Grand Masters 2026', TourEventCategory.live),
  _event('ev-d', 'European Club Cup 2026', TourEventCategory.live),
];

SpaceShortcut _pin(SpaceShortcut draft, String id, double sort) =>
    SpaceShortcut(
      id: id,
      kind: draft.kind,
      targetId: draft.targetId,
      title: draft.title,
      subtitle: draft.subtitle,
      params: draft.params,
      sortIndex: sort,
      createdAt: DateTime(2026, 9, 20),
    );

final _folder = SpaceShortcut(
  id: 'f',
  kind: SpaceShortcutKind.folder,
  targetId: 'folder-1',
  title: 'Najdorf prep',
  subtitle: '212 games',
  sortIndex: 5,
  createdAt: DateTime(2026, 9, 20),
);

final _player = SpaceShortcut(
  id: 'p',
  kind: SpaceShortcutKind.player,
  targetId: '1503014',
  title: 'Carlsen, Magnus',
  params: const {
    'fideId': 1503014,
    'playerName': 'Carlsen, Magnus',
    'rating': 2837,
    'title': 'GM',
  },
  sortIndex: 4,
  createdAt: DateTime(2026, 9, 24),
);

const _likes = SpaceShortcut(
  id: 'l',
  kind: SpaceShortcutKind.likes,
  targetId: 'me',
  title: 'Liked games',
  sortIndex: 3,
);

const _streak = SpaceShortcut(
  id: 's',
  kind: SpaceShortcutKind.streak,
  targetId: '1503014',
  title: 'Magnus Carlsen',
  sortIndex: 2,
);

const _link = SpaceShortcut(
  id: 'k',
  kind: SpaceShortcutKind.link,
  targetId: 'https://chessever.com/players/1503014',
  title: 'Carlsen scorecard',
  sortIndex: 1,
);

Future<_FakeSpaceShortcuts> _pumpSpace(
  WidgetTester tester,
  List<SpaceShortcut> seed, {
  ThemeData? theme,
  List<String> liveEvents = const [],
  Map<String, List<GamesTourModel>> eventGames = const {},
  List<GamesTourModel> playerGames = const [],
  _Favorites? favorites,
  Map<String, int> visits = const {},
  GamesListViewMode mode = GamesListViewMode.chessBoardGrid,
  double height = 2400,
  List<Override> extra = const [],
  Widget body = const MySpaceView(),
  _FakeSpaceShortcuts? store,
  Size screen = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(screen.width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  store ??= _FakeSpaceShortcuts(seed);
  final shortcuts = store;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => shortcuts),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
        currentUserProvider.overrideWithValue(null),
        likedGamesProvider.overrideWith(_NoLikes.new),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
        favoritePlayersProviderNew.overrideWith(
          () => favorites ?? _Favorites(),
        ),
        spacePlayerVisitsProvider.overrideWith(() => _Visits(visits)),
        forYouEventsProvider.overrideWith((ref) => _Feed(_feed)),
        libraryFolderAuthenticatedUserIdProvider.overrideWith((ref) => null),
        twicDatabaseTotalGamesProvider.overrideWith((ref) async => 9812345),
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(liveEvents),
        ),
        liveRoundsIdProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
        spaceEventBroadcastsProvider.overrideWith(
          (ref, ids) async => const <GroupBroadcast>[],
        ),
        spacePlayersLiveGamesProvider.overrideWith(
          (ref, ids) async => playerGames,
        ),
        spaceLiveEventGamesProvider.overrideWith(
          (ref, ids) async => SpaceLiveEventGames(
            byEvent: {
              for (final id in ids.ids)
                if (eventGames[id] case final games?)
                  id: ForYouEventGamesSnapshot(
                    eventId: id,
                    tourId: 'tour-$id',
                    visibleGames: games,
                    pinnedIds: const [],
                  ),
            },
          ),
        ),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
        ),
        gameCardEvalWithStockfishFallbackProvider.overrideWith(
          (ref, fen) async => _eval(fen),
        ),
        gameCardEvalCacheOnlyProvider.overrideWith(
          (ref, fen) async => _eval(fen),
        ),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        engineSettingsProviderNew.overrideWith(_EngineSettings.new),
        gamesListViewModeProvider.overrideWithValue(mode),
        eventImageProvider.overrideWith(
          (ref, id) async => const EventImageData(),
        ),
        eventNextRoundProvider.overrideWith((ref, id) async => null),
        ...extra,
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        // A phone, however tall the test view is (a tall view would read as
        // a tablet).
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: screen, textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              body: body,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
  return store;
}

/// No Spoilers off, without a Supabase read.
class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

/// A finished archive game between two players, with a position to draw.
GamesTourModel _game(String id, {required int whiteFide, int blackFide = 7}) {
  PlayerCard player(String name, int fide) => PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: 2800,
    countryCode: 'NO',
    team: null,
    fideId: fide,
  );
  return GamesTourModel(
    gameId: id,
    source: GameSource.gamebase,
    whitePlayer: player('Carlsen, Magnus', whiteFide),
    blackPlayer: player('Other, Player', blackFide),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'round-1',
    tourId: 'tour-1',
    fen: '6k1/5pp1/7p/3P4/1r6/6P1/5PKP/3R4 w - - 0 38',
    lastMove: 'e2e4',
  );
}

/// Lets the art's ticker, springs and any snack run out before teardown.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 6));
}

List<String> _groupTitles(WidgetTester tester) => [
  for (final e in find.byType(SpaceSectionHeader).evaluate())
    (e.widget as SpaceSectionHeader).title,
];

/// Lets Edit's springs (the lane, a check, a lifted card landing) run out.
Future<void> _settleEdit(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// My Space over [seed], then [section]'s See all pushed over it.
Future<_FakeSpaceShortcuts> _openSeeAll(
  WidgetTester tester,
  List<SpaceShortcut> seed,
  SpaceSection section, {
  _Favorites? favorites,
  GamesListViewMode mode = GamesListViewMode.chessBoardGrid,
  List<Override> extra = const [],
  List<String> liveEvents = const [],
  Map<String, List<GamesTourModel>> eventGames = const {},
  _FakeSpaceShortcuts? store,
  double height = 2400,
}) async {
  final opened = await _pumpSpace(
    tester,
    seed,
    favorites: favorites,
    mode: mode,
    extra: extra,
    liveEvents: liveEvents,
    eventGames: eventGames,
    store: store,
    height: height,
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  SpaceSectionScreen(section: section, pinsOnly: true),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return opened;
}

/// The keys of the cards Edit has selected, as their circles show them.
Set<String> _selectedKeys(WidgetTester tester) => {
  for (final e in find.byType(SpaceEditCheck).evaluate())
    if ((e.widget as SpaceEditCheck).selected)
      ((e.widget as SpaceEditCheck).key! as ValueKey<String>).value.substring(
        'space_edit_check_'.length,
      ),
};

/// The page's (or Edit's) own list: the outermost scrollable under [of].
ScrollPosition _listOf(WidgetTester tester, Finder of) => tester
    .state<ScrollableState>(
      find.descendant(of: of, matching: find.byType(Scrollable)).first,
    )
    .position;

/// Where [check] should stand on [card]: over the top-left square of the
/// card's board, as wide as it.
Rect _expectedCheck(WidgetTester tester, Finder card) {
  final box = tester.renderObject<RenderBox>(card);
  final board = spaceEditBoardIn(box)!;
  final at = spaceEditBoardCheckRect(
    board,
    kSpaceEditCheck,
    kSpaceEditBoardInset,
  );
  return at.shift(box.localToGlobal(Offset.zero));
}

/// A saved Smart Event of every game averaging [minElo]+.
SpaceShortcut _smartDraft(int minElo) => smartEventSpaceDraft(
  SmartEventRequest(
    source: SmartEventSource.forYou,
    tierLabel: '$minElo+',
    titleSuffix: 'Games',
    minElo: minElo,
    maxElo: 3200,
    caption: 'From your $minElo+ filter',
    countSingular: 'event',
    countPlural: 'events',
    events: const [],
    savedAt: DateTime(2026, 9, 24, 10),
  ),
);

/// Smart Events gather nothing today (no broadcast read).
final Override _noSmartMembers = discoverySmartEventMembersProvider
    .overrideWith((ref, criteria) async => const <GroupEventCardModel>[]);

void main() {
  testWidgets(
    'an empty space: captioned tiles, the explainer, three live events to save, and the Smart Event tile last',
    (tester) async {
      await _pumpSpace(tester, const []);

      expect(find.text('My Likes'), findsOneWidget);
      expect(find.text('No likes yet'), findsOneWidget);
      expect(find.text('My Prep'), findsOneWidget);
      // A guest's My Prep counts the master database.
      expect(find.text('9.8M master games'), findsOneWidget);
      // Adding lives on the floating "+" (home's FAB slot), not a header row.
      expect(find.text('My Database'), findsNothing);
      expect(find.text('Add'), findsNothing);
      expect(find.text(kMyDatabaseEmptyText), findsOneWidget);
      // Live and upcoming only, at most three, finished events left out.
      expect(find.byType(EventCard), findsNWidgets(kMySpaceSuggestions));
      expect(find.byType(SpaceSaveToggle), findsNWidgets(kMySpaceSuggestions));
      expect(find.text('Norway Chess 2026'), findsNothing);
      expect(find.byType(SpaceSectionHeader), findsNothing);
      final build = tester.getTopLeft(find.text('Build smart event')).dy;
      final lastCard = tester.getBottomLeft(find.byType(EventCard).last).dy;
      expect(build, greaterThan(lastCard));
      expect(find.text(kBuildSmartEventCaption), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _drain(tester);
    },
  );

  testWidgets('saving a suggested event makes it the Events group', (
    tester,
  ) async {
    final store = await _pumpSpace(tester, const []);

    await tester.tap(find.byType(SpaceSaveToggle).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final saved = store.state.valueOrNull ?? const [];
    expect(saved.map((s) => s.key), [eventSpaceDraft(_feed.first).key]);
    expect(_groupTitles(tester), ['Events']);
    expect(find.text(kMyDatabaseEmptyText), findsNothing);
    expect(find.text('Sinquefield Cup 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('saved things are grouped by type in page order; My Likes and '
      'streak pins stay out; every group is one sideways rail with See all', (
    tester,
  ) async {
    final events = [
      for (final (i, e) in _feed.take(4).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    final opening = _pin(
      spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'),
      'o',
      6,
    );
    await _pumpSpace(tester, [
      _link,
      _folder,
      _likes,
      _player,
      _streak,
      opening,
      ...events,
    ]);

    expect(_groupTitles(tester), [
      'Events',
      'Players',
      'Openings',
      'Databases',
      'Shortcuts',
    ]);
    expect(find.text('Liked games'), findsNothing);
    expect(find.text('Magnus Carlsen'), findsNothing);
    // Every group offers See all, whatever it shows.
    expect(
      find.textContaining('See all', findRichText: true),
      findsNWidgets(5),
    );
    // Events: one sideways rail, the first card on screen and the next
    // peeking at its edge.
    final rail = find.byKey(const PageStorageKey<String>('space_rail_events'));
    expect(rail, findsOneWidget);
    expect(tester.widget<ListView>(rail).scrollDirection, Axis.horizontal);
    final cards = find.descendant(of: rail, matching: find.byType(EventCard));
    expect(cards, findsWidgets);
    final screen = tester.getSize(find.byType(MySpaceView)).width;
    final second = tester.getTopLeft(cards.at(1)).dx;
    expect(second, lessThan(screen));
    expect(screen - second, greaterThan(40), reason: 'a peek, not a sliver');
    // A player is a face with a surname, never a pixel row.
    expect(find.text('Carlsen'), findsOneWidget);
    expect(find.text('2837'), findsOneWidget);
    expect(find.byType(SpaceSavedRow), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a saved player\'s game already drawn under a saved live '
      'event is drawn once, under its event\'s card in the Events rail; the '
      'rest stand in the Players group\'s own live rail and read who is at '
      'the board', (tester) async {
    final underEvent = _game('g-event', whiteFide: 1503014);
    final elsewhere = _game('g-other', whiteFide: 1503014, blackFide: 9);
    await _pumpSpace(
      tester,
      [_pin(eventSpaceDraft(_feed.first), 'e0', 20), _player],
      liveEvents: ['ev-a'],
      eventGames: {
        'ev-a': [underEvent],
      },
      playerGames: [underEvent, elsewhere],
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The event's board stands in the Events rail itself, under its own
    // event's card: the two scroll as one.
    final eventsRail = find.byKey(
      const PageStorageKey<String>('space_rail_events'),
    );
    final eventBoard = find.descendant(
      of: eventsRail,
      matching: find.byKey(const ValueKey('space_event_board_ev-a_g-event')),
    );
    expect(eventBoard, findsOneWidget);
    expect(find.byKey(const ValueKey('space_events_live_rail')), findsNothing);
    final card = find.descendant(
      of: eventsRail,
      matching: find.byType(EventCard),
    );
    expect(
      tester.getTopLeft(eventBoard).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(card).dy),
    );
    expect(
      tester.getTopLeft(eventBoard).dx,
      closeTo(tester.getTopLeft(card).dx, 1),
    );
    // The Players group's live rail draws only the other game, under the
    // faces.
    expect(
      find.byKey(const ValueKey('space_player_board_g-event')),
      findsNothing,
    );
    final board = find.descendant(
      of: find.byKey(const ValueKey('space_players_live_rail')),
      matching: find.byKey(const ValueKey('space_player_board_g-other')),
    );
    expect(board, findsOneWidget);
    expect(
      tester.getTopLeft(board).dy,
      greaterThan(tester.getBottomLeft(find.byType(SpacePlayerFace)).dy),
    );
    // The face reads LIVE while its player is at the board.
    expect(
      find.descendant(
        of: find.byType(SpacePlayerFace),
        matching: find.text('LIVE'),
      ),
      findsOneWidget,
    );
    // The line says who is at the board (its words may give way on a
    // narrow card; the whole sentence is always its label).
    final lines = tester.widgetList<DiscoveryCardMeta>(
      find.descendant(of: board, matching: find.byType(DiscoveryCardMeta)),
    );
    expect(lines.map((l) => l.semanticsLabel), ['Carlsen playing now']);
    // At a grid card's width the words that say why stay on the line (the
    // names give way first: "Carlsen · playing now", else "Playing now").
    expect(
      find.descendant(
        of: board,
        matching: find.textContaining(
          RegExp('playing now', caseSensitive: false),
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('each live event\'s card stands over its own boards in the '
      'Events rail and holds at the gutter while they scroll; the events that '
      'are not live stand stacked beside them', (tester) async {
    await _pumpSpace(
      tester,
      [
        _pin(eventSpaceDraft(_feed[0]), 'e0', 20),
        _pin(eventSpaceDraft(_feed[1]), 'e1', 19),
        _pin(eventSpaceDraft(_feed[2]), 'e2', 18),
        _pin(eventSpaceDraft(_feed[3]), 'e3', 17),
      ],
      liveEvents: ['ev-a', 'ev-b'],
      eventGames: {
        'ev-a': [for (var i = 0; i < 4; i++) _game('a$i', whiteFide: 40 + i)],
        'ev-b': [for (var i = 0; i < 3; i++) _game('b$i', whiteFide: 50 + i)],
      },
    );
    await tester.pump(const Duration(milliseconds: 100));
    final rail = find.byKey(const PageStorageKey<String>('space_rail_events'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: rail, matching: find.byType(Scrollable)),
        )
        .position;
    Rect card(String title) => tester.getRect(
      find.ancestor(of: find.text(title), matching: find.byType(EventCard)),
    );
    Rect board(String id) =>
        tester.getRect(find.byKey(ValueKey<String>('space_event_board_$id')));
    final gutter = card('Sinquefield Cup 2026').left;

    // The first live event's boards start under its card.
    expect(board('ev-a_a0').left, closeTo(gutter, 1));
    expect(
      board('ev-a_a0').top,
      greaterThan(card('Sinquefield Cup 2026').bottom),
    );

    // Scrolled into its boards, the card holds at the gutter over them...
    position.jumpTo(board('ev-a_a1').left - gutter + position.pixels);
    await tester.pump();
    expect(card('Sinquefield Cup 2026').left, closeTo(gutter, 0.5));
    expect(board('ev-a_a1').left, closeTo(gutter, 1));
    // ...until the end of its boards carries it off, flush with the last.
    position.jumpTo(board('ev-a_a3').left - gutter + position.pixels);
    await tester.pump();
    expect(
      card('Sinquefield Cup 2026').right,
      closeTo(board('ev-a_a3').right, 1),
    );

    // On to the next live event: its card stands over its own boards.
    position.jumpTo(board('ev-b_b0').left - gutter + position.pixels);
    await tester.pump();
    expect(card('FIDE Grand Swiss 2026').left, closeTo(gutter, 0.5));
    expect(card('Sinquefield Cup 2026').right, lessThan(gutter));

    // The events that are not live close the rail, one over the other.
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    final norway = card('Norway Chess 2026');
    final chennai = card('Chennai Grand Masters 2026');
    expect(norway.left, closeTo(chennai.left, 0.5));
    expect(chennai.top, greaterThan(norway.bottom));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a new user who follows players keeps the explainer and the '
      'live events to save until they save something', (tester) async {
    final store = await _pumpSpace(
      tester,
      const [],
      favorites: _Favorites([_follow('Carlsen, Magnus', 1503014, 2837)]),
    );
    expect(_groupTitles(tester), ['Players']);
    expect(find.text(kMyDatabaseEmptyText), findsOneWidget);
    expect(find.byType(SpaceSaveToggle), findsNWidgets(kMySpaceSuggestions));
    // The suggestions stand where the Events group will, above the faces.
    expect(
      tester.getTopLeft(find.byType(SpaceSaveToggle).last).dy,
      lessThan(tester.getTopLeft(find.text('Players')).dy),
    );

    // Anything saved and they give way.
    await store.add(_folder);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_groupTitles(tester), ['Players', 'Databases']);
    expect(find.text(kMyDatabaseEmptyText), findsNothing);
    expect(find.byType(SpaceSaveToggle), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a saved event is LIVE by the live feed only, never by the '
      'category it was saved with', (tester) async {
    await _pumpSpace(tester, [_pin(eventSpaceDraft(_feed.first), 'e0', 20)]);
    expect(find.text('LIVE'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('space_event_board_'),
      ),
      findsNothing,
    );
    expect(
      spaceEventCardModelFromShortcut(
        eventSpaceDraft(_feed.first),
      ).tourEventCategory,
      TourEventCategory.ongoing,
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('See all is the group at full length, in its own cards; Edit '
      'keeps those cards and circles each one, and Done ends it', (
    tester,
  ) async {
    final events = [
      for (final (i, e) in _feed.take(4).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    await _pumpSpace(tester, events);

    await tester.tap(find.textContaining('See all', findRichText: true));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SpaceSectionScreen), findsOneWidget);
    Finder cards() => find.descendant(
      of: find.byType(SpaceSectionScreen),
      matching: find.byType(EventCard),
    );
    expect(cards(), findsNWidgets(4));
    // Reorder is gone: the page offers Edit (and Add).
    expect(find.text('Reorder', findRichText: true), findsNothing);
    expect(find.byType(SpaceEditCheck), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    // The same cards, each behind its circle; nothing selected yet, so
    // Remove waits and Add steps aside for Done.
    expect(cards(), findsNWidgets(4));
    expect(find.byType(SpaceEditCheck), findsNWidgets(4));
    expect(find.text('Remove', findRichText: true), findsOneWidget);
    expect(find.text('Done', findRichText: true), findsOneWidget);
    expect(find.text('Add', findRichText: true), findsNothing);
    // The circles stand in a lane before the cards, whole and on screen.
    for (final e in find.byType(SpaceEditCheck).evaluate()) {
      final check = tester.getRect(find.byWidget(e.widget));
      expect(check.left, greaterThanOrEqualTo(15.5));
      expect(check.width, closeTo(check.height, 0.01));
    }
    final card = tester.getRect(cards().first);
    final check = tester.getRect(find.byType(SpaceEditCheck).first);
    expect(check.right, lessThan(card.left));
    expect(check.center.dy, closeTo(card.center.dy, 1));

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(find.text('Edit', findRichText: true), findsOneWidget);
    expect(cards(), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Edit selects a card with a tap (never opens it); Remove takes '
      'the selected out with one Undo for all of them', (tester) async {
    final events = [
      for (final (i, e) in _feed.take(4).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    final store = await _openSeeAll(tester, events, SpaceSection.events);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);

    final a = events[1].key;
    final b = events[3].key;
    await tester.tap(find.text(_feed[1].title));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text(_feed[3].title));
    await _settleEdit(tester);
    // Still on See all: a tap in Edit selects, it does not open the event.
    expect(find.byType(SpaceSectionScreen), findsOneWidget);
    expect(_selectedKeys(tester), {a, b});
    expect(find.text('Remove 2', findRichText: true), findsOneWidget);
    // A screen reader hears the card and that it is selected.
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(ValueKey<String>('space_edit_check_$a'))),
      isSemantics(label: _feed[1].title, isSelected: true, isButton: true),
    );
    semantics.dispose();

    // A second tap clears one again.
    await tester.tap(find.text(_feed[3].title));
    await _settleEdit(tester);
    expect(_selectedKeys(tester), {a});
    await tester.tap(find.text(_feed[3].title));
    await _settleEdit(tester);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.events), isNot(contains(a)));
    expect(store.keysOf(SpaceSection.events), isNot(contains(b)));
    expect(find.text(_feed[1].title), findsNothing);
    expect(find.text('Removed 2 from My Space'), findsOneWidget);
    // Still in Edit, nothing selected.
    expect(find.byType(SpaceEditCheck), findsNWidgets(2));
    expect(find.text('Remove', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.events).toSet(), {
      for (final e in events) e.key,
    });
    expect(find.byType(SpaceEditCheck), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('removing every card ends Edit on the empty group', (
    tester,
  ) async {
    final events = [
      for (final (i, e) in _feed.take(2).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    final store = await _openSeeAll(tester, events, SpaceSection.events);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    for (final e in _feed.take(2)) {
      await tester.tap(find.text(e.title));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.events), isEmpty);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(find.text('Done', findRichText: true), findsNothing);
    expect(find.text('Nothing in Events yet'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('in Edit a hold lifts a card and a drag puts it in a new '
      'place: the others glide aside and the store keeps the order', (
    tester,
  ) async {
    final events = [
      for (final (i, e) in _feed.take(3).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    final store = await _openSeeAll(tester, events, SpaceSection.events);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);

    final first = find.text(_feed[0].title);
    final second = tester.getRect(
      find.ancestor(
        of: find.text(_feed[1].title),
        matching: find.byType(EventCard),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(first));
    // A hold lifts it: its place turns into a socket.
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 60));
    expect(
      find.byKey(ValueKey<String>('space_edit_socket_${events[0].key}')),
      findsOneWidget,
    );
    // Carried past the second card's middle.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, (second.height + 12) / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.events), [
      events[1].key,
      events[0].key,
      events[2].key,
    ]);
    // Landed: no socket left, and the page shows the stored order.
    expect(
      find.byKey(ValueKey<String>('space_edit_socket_${events[0].key}')),
      findsNothing,
    );
    expect(
      tester.getCenter(find.text(_feed[1].title)).dy,
      lessThan(tester.getCenter(find.text(_feed[0].title)).dy),
    );
    // A drag never selects.
    expect(_selectedKeys(tester), isEmpty);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('in grid view Edit keeps two games to a row, and a game '
      'dragged across the row lands in the other column', (tester) async {
    final games = [
      _pin(gameSpaceShortcutDraft(_game('g-1', whiteFide: 21))!, 'g1', 9),
      _pin(gameSpaceShortcutDraft(_game('g-2', whiteFide: 22))!, 'g2', 8),
      _pin(gameSpaceShortcutDraft(_game('g-3', whiteFide: 23))!, 'g3', 7),
    ];
    final store = await _openSeeAll(tester, games, SpaceSection.games);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);

    final cards = find.byType(GridGameCardWrapperWidget);
    expect(cards, findsNWidgets(3));
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    final one = tester.getRect(cards.at(0));
    final two = tester.getRect(cards.at(1));
    final three = tester.getRect(cards.at(2));
    expect(two.left, greaterThan(one.right));
    expect(two.top, closeTo(one.top, 0.5));
    expect(three.top, greaterThan(one.bottom));
    // Each card whole inside the screen.
    for (final r in [one, two, three]) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(390));
    }

    final gesture = await tester.startGesture(one.center);
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 60));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset((two.center.dx - one.center.dx) / 5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.games), [
      games[1].key,
      games[0].key,
      games[2].key,
    ]);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Players Edit takes a followed player out of My Space only: '
      'never unfollowed, Undo brings the face back, and faces keep their '
      'own order (nothing lifts)', (tester) async {
    final favorites = _Favorites([
      _follow('Carlsen, Magnus', 1503014, 2837),
      _follow('Gukesh D', 46616543, 2787, day: 2),
    ]);
    await _openSeeAll(
      tester,
      const [],
      SpaceSection.players,
      favorites: favorites,
    );
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNWidgets(2));
    // The circle sits on the face's rim, top left, clear of the screen edge.
    final face = tester.getRect(find.byType(SpacePlayerFace).first);
    final check = tester.getRect(find.byType(SpaceEditCheck).first);
    expect(check.left, greaterThan(0));
    expect(check.center.dx, lessThan(face.center.dx));
    expect(check.top, lessThan(face.top + 20));

    // A hold does not lift a face.
    final hold = await tester.startGesture(
      tester.getCenter(find.text('Gukesh')),
    );
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 100));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('space_edit_socket_'),
      ),
      findsNothing,
    );
    await hold.up();
    await _settleEdit(tester);
    // Held and let go in place, a face is only tapped: selected, and a tap
    // clears it again.
    expect(find.text('Remove 1', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Gukesh'));
    await _settleEdit(tester);
    expect(find.text('Remove', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Carlsen'));
    await _settleEdit(tester);
    expect(find.text('Remove 1', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(find.text('Carlsen'), findsNothing);
    expect(find.text('Gukesh'), findsOneWidget);
    expect(favorites.unfollows, 0);
    expect(find.text('Removed from My Space'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settleEdit(tester);
    expect(find.text('Carlsen'), findsOneWidget);
    expect(favorites.unfollows, 0);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a See all page\'s first Edit teaches itself once: Players '
      'start at selecting (they order themselves), Edit works after, and '
      'the next page that reorders still teaches holding', (tester) async {
    final tips = _Tips();
    final favorites = _Favorites([
      _follow('Carlsen, Magnus', 1503014, 2837),
      _follow('Gukesh D', 46616543, 2787, day: 2),
    ]);
    await _openSeeAll(
      tester,
      const [],
      SpaceSection.players,
      favorites: favorites,
      extra: [spaceEditTutorialStoreProvider.overrideWithValue(tips)],
    );
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditTutorial), findsOneWidget);
    expect(tips.playersShownCount, 1);
    // The Players' tips do not retire the whole tips.
    expect(tips.shown, 0);
    final dots = tester.widget<TutorialStepIndicator>(
      find.byType(TutorialStepIndicator),
    );
    expect(dots.totalSteps, 3);
    expect(find.text('Hold to Reorder'), findsNothing);

    final next = find.byKey(const ValueKey<String>('space_edit_tips_next'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(next);
      await _settleEdit(tester);
    }
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settleEdit(tester);
    expect(find.byType(SpaceEditTutorial), findsNothing);

    // The face takes the tap over its name.
    await tester.tap(find.text('Carlsen'), warnIfMissed: false);
    await _settleEdit(tester);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(find.text('Carlsen'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditTutorial), findsNothing);
    expect(tips.playersShownCount, 1);
    expect(tester.takeException(), isNull);
    await _drain(tester);

    // Events reorder: their first Edit teaches the one step the Players'
    // tips left out, alone, and then no more.
    await _openSeeAll(
      tester,
      [_pin(eventSpaceDraft(_feed.first), 'e0', 20)],
      SpaceSection.events,
      extra: [spaceEditTutorialStoreProvider.overrideWithValue(tips)],
    );
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditTutorial), findsOneWidget);
    expect(find.text('Hold to Reorder'), findsOneWidget);
    expect(find.text('Tap to Select'), findsNothing);
    expect(find.byType(TutorialStepIndicator), findsNothing);
    expect(
      find.descendant(of: next, matching: find.text('Got it')),
      findsOneWidget,
    );
    expect(tips.shown, 1);
    await tester.tap(next);
    await tester.pump(SpaceEditTutorial.fadeOut);
    await _settleEdit(tester);
    expect(find.byType(SpaceEditTutorial), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditTutorial), findsNothing);
    expect(tips.shown, 1);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('every See all page offers Edit, and each one circles its own '
      'cards', (tester) async {
    final seed = [
      _pin(eventSpaceDraft(_feed.first), 'e0', 20),
      _pin(gameSpaceShortcutDraft(_game('g-3', whiteFide: 21))!, 'g3', 9),
      _pin(spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'), 'o1', 7),
      _folder,
      _link,
      _pin(_smartDraft(2700), 'se1', 1),
    ];
    for (final section in [
      SpaceSection.events,
      SpaceSection.games,
      SpaceSection.openings,
      SpaceSection.library,
      SpaceSection.links,
      SpaceSection.smartEvents,
    ]) {
      await _openSeeAll(tester, seed, section, extra: [_noSmartMembers]);
      await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
      await _settleEdit(tester);
      expect(find.byType(SpaceEditCheck), findsOneWidget, reason: '$section');
      await tester.tap(find.byType(SpaceEditCheck));
      await _settleEdit(tester);
      expect(
        find.text('Remove 1', findRichText: true),
        findsOneWidget,
        reason: '$section',
      );
      expect(tester.takeException(), isNull, reason: '$section');
      await _drain(tester);
    }
  });

  testWidgets('My Prep\'s Openings (the Openings group\'s See all) edits the '
      'same way: select, Remove with Undo, and a hold moves a line', (
    tester,
  ) async {
    final lines = [
      _pin(spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'), 'o1', 7),
      _pin(
        spaceOpeningDraft(targetId: 'B90', name: 'Sicilian Najdorf'),
        'o2',
        6,
      ),
      _pin(
        spaceOpeningDraft(
          targetId: 'E97',
          name: "King's Indian, Mar del Plata",
        ),
        'o3',
        5,
      ),
    ];
    final store = await _pumpSpace(
      tester,
      lines,
      mode: GamesListViewMode.gamesCard,
      body: const MyPrepOpeningsPage(),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SpaceOpeningCard), findsNWidgets(3));
    expect(find.text('Edit', findRichText: true), findsOneWidget);
    expect(find.text('Add', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    expect(find.byType(SpaceOpeningCard), findsNWidgets(3));

    // A hold carries the first line under the second.
    final one = tester.getRect(find.byType(SpaceOpeningCard).at(0));
    final two = tester.getRect(find.byType(SpaceOpeningCard).at(1));
    final gesture = await tester.startGesture(one.center);
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 60));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, (two.center.dy - one.center.dy) / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.openings), [
      lines[1].key,
      lines[0].key,
      lines[2].key,
    ]);

    await tester.tap(find.byType(SpaceEditCheck).last);
    await _settleEdit(tester);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.openings), hasLength(2));
    expect(find.text('Removed from My Space'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.openings), hasLength(3));

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Edit shows the order See all shows (live events first), a '
      'drag stays in its run, and the page keeps the drop after Done', (
    tester,
  ) async {
    final events = [
      for (final (i, e) in _feed.take(4).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    // Norway, third in store order, is the one live now.
    final store = await _openSeeAll(
      tester,
      events,
      SpaceSection.events,
      liveEvents: [_feed[2].id],
    );
    final titles = [for (final e in _feed.take(4)) e.title];
    List<String> shown() {
      final ys = {for (final t in titles) t: tester.getCenter(find.text(t)).dy};
      return [...titles]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
    }

    final page = shown();
    expect(page, [titles[2], titles[0], titles[1], titles[3]]);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNWidgets(4));
    // Nothing reshuffles as Edit starts.
    expect(shown(), page);

    // The last card, carried all the way up, stops at the top of its run:
    // under the live event, never above it.
    final from = tester.getCenter(find.text(titles[3]));
    final to = tester.getTopLeft(find.text(titles[2])).dy - 60;
    final gesture = await tester.startGesture(from);
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 60));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(0, (to - from.dy) / 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settleEdit(tester);
    final dropped = [titles[2], titles[3], titles[0], titles[1]];
    expect(shown(), dropped);
    expect(store.keysOf(SpaceSection.events), [
      events[3].key,
      events[0].key,
      events[1].key,
      events[2].key,
    ]);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    // The page stands in the order the drop left.
    expect(shown(), dropped);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a saved game the page can only draw as its row stands last in '
      'Edit too, and moves only among its own kind', (tester) async {
    final lost = SpaceShortcut(
      id: 'lost',
      kind: SpaceShortcutKind.game,
      targetId: 'lost-1',
      title: 'Lost game',
      sortIndex: 30,
      createdAt: DateTime(2026, 9, 20),
    );
    final games = [
      lost,
      _pin(gameSpaceShortcutDraft(_game('g-1', whiteFide: 21))!, 'g1', 9),
      _pin(gameSpaceShortcutDraft(_game('g-2', whiteFide: 22))!, 'g2', 8),
    ];
    final store = await _openSeeAll(
      tester,
      games,
      SpaceSection.games,
      extra: [spaceGameCardProvider.overrideWith((ref, key) async => null)],
    );
    final cards = find.byType(GridGameCardWrapperWidget);
    expect(cards, findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Lost game')).dy,
      greaterThan(tester.getRect(cards.first).bottom),
    );

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    // Where the page has it: under the cards, as its row.
    final row = tester.getRect(find.text('Lost game'));
    expect(row.top, greaterThan(tester.getRect(cards.first).bottom));

    // Carried above the cards, it comes back to its own run.
    final gesture = await tester.startGesture(row.center);
    await tester.pump(kSpaceEditLiftDelay + const Duration(milliseconds: 60));
    final up = tester.getRect(cards.first).top - row.center.dy;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, up / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.games), [
      lost.key,
      games[1].key,
      games[2].key,
    ]);
    expect(
      tester.getTopLeft(find.text('Lost game')).dy,
      greaterThan(tester.getRect(cards.first).bottom),
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('grid Edit keeps every card where the page has it, at its '
      'width, its circle on its board; Done sees the circles off in place', (
    tester,
  ) async {
    final games = [
      _pin(gameSpaceShortcutDraft(_game('g-1', whiteFide: 21))!, 'g1', 9),
      _pin(gameSpaceShortcutDraft(_game('g-2', whiteFide: 22))!, 'g2', 8),
      _pin(gameSpaceShortcutDraft(_game('g-3', whiteFide: 23))!, 'g3', 7),
    ];
    await _openSeeAll(tester, games, SpaceSection.games);
    final cards = find.byType(GridGameCardWrapperWidget);
    final page = [for (var i = 0; i < 3; i++) tester.getRect(cards.at(i))];

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    for (var i = 0; i < 3; i++) {
      expect(tester.getRect(cards.at(i)), rectMoreOrLessEquals(page[i]));
      final check = tester.getRect(
        find.byKey(ValueKey<String>('space_edit_check_${games[i].key}')),
      );
      // On the card's board: inside the card, under its name line, at the
      // board's left, over its top-left square.
      expect(check.left, greaterThan(page[i].left));
      expect(check.top, greaterThan(page[i].top + 16));
      expect(check.right, lessThan(page[i].center.dx));
      expect(check.bottom, lessThan(page[i].center.dy));
      expect(
        check,
        rectMoreOrLessEquals(
          _expectedCheck(
            tester,
            find.byKey(ValueKey<String>('space_edit_game_${games[i].key}')),
          ),
          epsilon: 0.5,
        ),
      );
    }

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // The header is back at once; the circles go the way they came.
    expect(find.text('Edit', findRichText: true), findsOneWidget);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    for (var i = 0; i < 3; i++) {
      expect(tester.getRect(cards.at(i)), rectMoreOrLessEquals(page[i]));
    }
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Edit builds the cards a row at a time as they scroll in, as '
      'See all does', (tester) async {
    final games = [
      for (var i = 0; i < 30; i++)
        _pin(
          gameSpaceShortcutDraft(_game('g-$i', whiteFide: 100 + i))!,
          'g$i',
          60.0 - i,
        ),
    ];
    await _openSeeAll(
      tester,
      games,
      SpaceSection.games,
      mode: GamesListViewMode.chessBoard,
      height: 844,
    );
    Finder built(String key) => find.byKey(
      ValueKey<String>('space_edit_game_$key'),
      skipOffstage: false,
    );
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    final count = [
      for (final g in games)
        if (built(g.key).evaluate().isNotEmpty) g,
    ].length;
    expect(count, greaterThan(0));
    expect(count, lessThan(10));
    expect(built(games.last.key), findsNothing);

    // Scrolled to the end, the last game is built and the first is not.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -30000));
    await _settleEdit(tester);
    expect(built(games.last.key), findsOneWidget);
    expect(built(games.first.key), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Remove shows its Undo at once, before the server has '
      'answered; Undo puts the card back at once, in its place, and its row '
      'is written only once the delete has answered', (tester) async {
    final events = [
      for (final (i, e) in _feed.take(3).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    final store = _SlowRemoveStore(events);
    await _openSeeAll(tester, events, SpaceSection.events, store: store);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    await tester.tap(find.text(_feed[1].title), warnIfMissed: false);
    await _settleEdit(tester);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.answered, isFalse);
    expect(store.keysOf(SpaceSection.events), isNot(contains(events[1].key)));
    expect(find.text('Removed from My Space'), findsOneWidget);

    // Undo before the server has answered: the card is back at once, in
    // its place, and nothing is written over the delete still on the wire.
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.keysOf(SpaceSection.events), [for (final e in events) e.key]);
    expect(find.text(_feed[1].title), findsOneWidget);
    expect(store.serverWrites, isEmpty);
    store.answer();
    await _settleEdit(tester);
    expect(store.serverWrites, [events[1].key]);
    expect(store.keysOf(SpaceSection.events), [for (final e in events) e.key]);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Undo after removing several cards puts every one back in '
      'its own place, in the list and on the page', (tester) async {
    final events = [
      for (final (i, e) in _feed.indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    final store = await _openSeeAll(tester, events, SpaceSection.events);
    final before = store.keysOf(SpaceSection.events);
    List<String> shown() {
      final ys = {
        for (final e in _feed) e.title: tester.getCenter(find.text(e.title)).dy,
      };
      return [for (final e in _feed) e.title]
        ..sort((a, b) => ys[a]!.compareTo(ys[b]!));
    }

    final page = shown();
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    // The first, the middle and the last.
    for (final i in [0, 2, 4]) {
      await tester.tap(find.text(_feed[i].title), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settleEdit(tester);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.events), [before[1], before[3]]);

    await tester.tap(find.text('Undo'));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.events), before);
    expect(shown(), page);

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(shown(), page);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('board view Edit keeps every game and line at its width and '
      'in its place, each circle covering its board\'s top-left square', (
    tester,
  ) async {
    final games = [
      _pin(gameSpaceShortcutDraft(_game('g-1', whiteFide: 21))!, 'g1', 9),
      _pin(gameSpaceShortcutDraft(_game('g-2', whiteFide: 22))!, 'g2', 8),
      _pin(gameSpaceShortcutDraft(_game('g-3', whiteFide: 23))!, 'g3', 7),
    ];
    await _openSeeAll(
      tester,
      games,
      SpaceSection.games,
      mode: GamesListViewMode.chessBoard,
    );
    final cards = find.byType(GameCardWrapperWidget);
    expect(cards, findsNWidgets(3));
    final page = [for (var i = 0; i < 3; i++) tester.getRect(cards.at(i))];

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      // Nothing shrinks and nothing moves.
      expect(tester.getRect(cards.at(i)), rectMoreOrLessEquals(page[i]));
      final card = find.byKey(
        ValueKey<String>('space_edit_game_${games[i].key}'),
      );
      final check = tester.getRect(
        find.byKey(ValueKey<String>('space_edit_check_${games[i].key}')),
      );
      final expected = _expectedCheck(tester, card);
      expect(check, rectMoreOrLessEquals(expected, epsilon: 0.5));
      // One square, whole: the board's own eighth, inside the card.
      final board = spaceEditBoardIn(tester.renderObject<RenderBox>(card))!;
      expect(check.width, closeTo(board.width / 8, 0.5));
      expect(check.left, greaterThan(page[i].left));
    }
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    for (var i = 0; i < 3; i++) {
      expect(tester.getRect(cards.at(i)), rectMoreOrLessEquals(page[i]));
    }
    expect(tester.takeException(), isNull);
    await _drain(tester);

    // My Prep's lines in board view do the same.
    final lines = [
      _pin(spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'), 'o1', 7),
      _pin(
        spaceOpeningDraft(targetId: 'B90', name: 'Sicilian Najdorf'),
        'o2',
        6,
      ),
    ];
    await _pumpSpace(
      tester,
      lines,
      mode: GamesListViewMode.chessBoard,
      body: const MyPrepOpeningsPage(),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final openings = find.byType(SpaceOpeningCard);
    final list = [for (var i = 0; i < 2; i++) tester.getRect(openings.at(i))];
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    for (var i = 0; i < 2; i++) {
      expect(tester.getRect(openings.at(i)), rectMoreOrLessEquals(list[i]));
      final check = tester.getRect(
        find.byKey(ValueKey<String>('space_edit_check_${lines[i].key}')),
      );
      expect(
        check,
        rectMoreOrLessEquals(
          _expectedCheck(tester, openings.at(i)),
          epsilon: 0.5,
        ),
      );
    }
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Done brings Events See all back where the reader was, though '
      'Edit (without the live boards) is far shorter', (tester) async {
    final events = [
      for (var i = 0; i < 8; i++)
        _event('ev-n$i', 'Event number $i', TourEventCategory.live),
    ];
    final pins = [
      for (final (i, e) in events.indexed)
        _pin(eventSpaceDraft(e), 'n$i', 40.0 - i),
    ];
    await _openSeeAll(
      tester,
      pins,
      SpaceSection.events,
      height: 844,
      liveEvents: [for (final e in events) e.id],
      eventGames: {
        for (final (i, e) in events.indexed)
          e.id: [
            for (var j = 0; j < 4; j++)
              _game('g-$i-$j', whiteFide: 1000 + 10 * i + j),
          ],
      },
    );
    final page = find.byType(SpaceGroupPage);
    await tester.drag(page, const Offset(0, -1500));
    await _settleEdit(tester);
    final before = _listOf(tester, page).pixels;
    expect(before, greaterThan(1000));

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    final edit = _listOf(tester, find.byType(SpaceGroupEdit));
    // Edit opens as near the reader's place as it reaches, at rest.
    expect(edit.pixels, lessThanOrEqualTo(edit.maxScrollExtent));

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(
      _listOf(tester, find.byType(SpaceGroupPage)).pixels,
      closeTo(before, 1),
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a group Edit lays out as its page opens where the reader is, '
      'and Done leaves the page where the reader left Edit', (tester) async {
    final games = [
      for (var i = 0; i < 30; i++)
        _pin(
          gameSpaceShortcutDraft(_game('g-$i', whiteFide: 100 + i))!,
          'g$i',
          60.0 - i,
        ),
    ];
    await _openSeeAll(
      tester,
      games,
      SpaceSection.games,
      mode: GamesListViewMode.chessBoard,
      height: 844,
    );
    final page = find.byType(SpaceGroupPage);
    await tester.drag(page, const Offset(0, -2400));
    await _settleEdit(tester);
    final before = _listOf(tester, page).pixels;
    expect(before, greaterThan(1500));

    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    final edit = find.byType(SpaceGroupEdit);
    expect(_listOf(tester, edit).pixels, closeTo(before, 1));

    await tester.drag(edit, const Offset(0, 900));
    await _settleEdit(tester);
    final left = _listOf(tester, edit).pixels;
    expect(left, lessThan(before - 500));

    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(
      _listOf(tester, find.byType(SpaceGroupPage)).pixels,
      closeTo(left, 1),
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('My Prep\'s count, Remove and Done stay put while Edit '
      'scrolls, so a line far down is selected and removed from there', (
    tester,
  ) async {
    const codes = ['C67', 'B90', 'E97', 'C42', 'D37', 'B12', 'C65', 'B33'];
    final lines = [
      for (final (i, c) in codes.indexed)
        _pin(spaceOpeningDraft(targetId: c, name: 'Line $c'), 'o$i', 20.0 - i),
    ];
    final store = await _pumpSpace(
      tester,
      lines,
      mode: GamesListViewMode.chessBoard,
      height: 844,
      body: const MyPrepOpeningsPage(),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    final done = tester.getRect(
      find.byKey(const ValueKey<String>('space_edit_done')),
    );
    final edit = find.byType(SpaceGroupEdit);
    await tester.drag(edit, const Offset(0, -2000));
    await _settleEdit(tester);
    expect(_listOf(tester, edit).pixels, greaterThan(1500));
    expect(
      tester.getRect(find.byKey(const ValueKey<String>('space_edit_done'))),
      done,
    );

    // A line down there, selected and removed without scrolling back.
    final far = lines[6].key;
    await tester.tap(find.byKey(ValueKey<String>('space_edit_check_$far')));
    await _settleEdit(tester);
    expect(find.text('Remove 1', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_remove')));
    await _settleEdit(tester);
    expect(store.keysOf(SpaceSection.openings), isNot(contains(far)));
    final left = _listOf(tester, edit).pixels;

    // Done leaves the lines where the reader left Edit.
    await tester.tap(find.byKey(const ValueKey<String>('space_edit_done')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(
      _listOf(tester, find.byType(MyPrepOpeningsPage)).pixels,
      closeTo(left, 1),
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a line\'s name keeps its descenders at 1.3x text on a small '
      'phone, in its grid card and in Edit', (tester) async {
    final lines = [
      _pin(
        spaceOpeningDraft(
          targetId: 'E97',
          name: "King's Indian, Mar del Plata",
        ),
        'o1',
        7,
      ),
      _pin(
        spaceOpeningDraft(targetId: 'B90', name: 'Sicilian Najdorf'),
        'o2',
        6,
      ),
    ];
    await _pumpSpace(
      tester,
      lines,
      screen: const Size(320, 568),
      textScale: 1.3,
      body: const MyPrepOpeningsPage(),
    );
    await tester.pump(const Duration(milliseconds: 100));
    void whole() {
      for (final name in ["King's Indian, Mar del Plata", 'Sicilian Najdorf']) {
        final text = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(SpaceOpeningCard),
            matching: find.text(name),
          ),
        );
        expect(
          text.size.height,
          greaterThanOrEqualTo(
            text.getMaxIntrinsicHeight(text.size.width) - 0.01,
          ),
          reason: '$name is cut',
        );
      }
    }

    whole();
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    whole();
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('back in Edit ends Edit first; back again leaves the page', (
    tester,
  ) async {
    final events = [
      for (final (i, e) in _feed.take(2).indexed)
        _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
    ];
    await _openSeeAll(tester, events, SpaceSection.events);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    await tester.tap(find.text(_feed[0].title), warnIfMissed: false);
    await _settleEdit(tester);

    // The system back (the route's maybePop, as Android's back runs it).
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await _settleEdit(tester);
    expect(find.byType(SpaceSectionScreen), findsOneWidget);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(find.text('Edit', findRichText: true), findsOneWidget);

    await navigator.maybePop();
    await _settleEdit(tester);
    expect(find.byType(SpaceSectionScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('back in My Prep\'s Openings Edit ends Edit, the page stays', (
    tester,
  ) async {
    final lines = [
      _pin(spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'), 'o1', 7),
      _pin(
        spaceOpeningDraft(targetId: 'B90', name: 'Sicilian Najdorf'),
        'o2',
        6,
      ),
    ];
    await _pumpSpace(tester, lines, body: const MyPrepOpeningsPage());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(find.byType(SpaceEditCheck), findsNWidgets(2));

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await _settleEdit(tester);
    expect(find.byType(MyPrepOpeningsPage), findsOneWidget);
    expect(find.byType(SpaceEditCheck), findsNothing);
    expect(find.text('Edit', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('in Edit the cards draw none of their own controls: no star on '
      'an event, no chevron on a saved row', (tester) async {
    final seed = [
      _pin(eventSpaceDraft(_feed[0]), 'e0', 20),
      _pin(eventSpaceDraft(_feed[1]), 'e1', 19),
      _folder,
    ];
    Finder stars() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_StarWidget',
    );
    Finder chevrons() => find.descendant(
      of: find.byType(SpaceSectionScreen),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );

    await _openSeeAll(tester, seed, SpaceSection.events);
    expect(stars(), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(stars(), findsNothing);
    await _drain(tester);

    await _openSeeAll(tester, seed, SpaceSection.library);
    expect(chevrons(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
    await _settleEdit(tester);
    expect(chevrons(), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Smart events are one sideways rail like every other group: '
      'the next card peeks, and the rail loads ten at a time', (tester) async {
    final smart = [
      for (var i = 0; i < 12; i++)
        _pin(_smartDraft(2000 + 100 * i), 'se$i', 30.0 - i),
    ];
    await _pumpSpace(tester, smart, extra: [_noSmartMembers], height: 1600);
    await tester.pump(const Duration(milliseconds: 100));
    final rail = find.byKey(
      const PageStorageKey<String>('space_rail_smart_events'),
    );
    expect(rail, findsOneWidget);
    final scrollable = tester.widget<ListView>(rail);
    expect(scrollable.scrollDirection, Axis.horizontal);
    final cards = find.descendant(
      of: rail,
      matching: find.byType(SmartEventCard),
    );
    expect(cards, findsWidgets);
    // Every card the same size, and the second peeking at the edge.
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(second.size.height, closeTo(first.size.height, 0.5));
    expect(second.width, closeTo(first.width, 0.5));
    expect(first.left, closeTo(16, 1));
    expect(second.left, lessThan(390));
    expect(second.right, greaterThan(390));

    // Ten a page, then the next as the rail nears its end.
    final state = tester.state<ScrollableState>(
      find.descendant(of: rail, matching: find.byType(Scrollable)),
    );
    for (var i = 0; i < 20; i++) {
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(ValueKey<String>('space_smart_${smart.last.key}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('holding a saved row offers Remove from My Space, and takes '
      'it out', (tester) async {
    await _pumpSpace(tester, [_folder]);

    await tester.longPress(find.text('Najdorf prep'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Remove from My Space'), findsOneWidget);
    await tester.tap(find.text('Remove from My Space'));
    // The menu lets go of its lifted copy, then the row leaves.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Najdorf prep'), findsNothing);
    expect(find.text(kMyDatabaseEmptyText), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('Build smart event opens the builder in place', (tester) async {
    await _pumpSpace(tester, const []);

    await tester.tap(find.text('Build smart event'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SmartEventBuilder), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Players are the followed players by default, the most '
      'recently visited first, the rest in Favorites\' order', (tester) async {
    await _pumpSpace(
      tester,
      const [],
      favorites: _Favorites([
        _follow('Carlsen, Magnus', 1503014, 2837),
        _follow('Gukesh D', 46616543, 2787, day: 2),
        _follow('Praggnanandhaa R', 25059530, 2767, day: 3),
      ]),
      visits: {
        spacePlayerIdentity(fideId: 46616543, name: 'Gukesh D'): DateTime(
          2026,
          9,
          25,
          10,
        ).millisecondsSinceEpoch,
      },
    );

    // Nothing pinned, yet the group stands, counting the faces it shows.
    expect(_groupTitles(tester), ['Players']);
    expect(find.bySemanticsLabel('Players, 3'), findsOneWidget);
    double x(String name) => tester.getTopLeft(find.text(name)).dx;
    expect(x('Gukesh'), lessThan(x('Carlsen')));
    expect(x('Carlsen'), lessThan(x('Praggnanandhaa')));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Remove from My Space hides a followed player here and never '
      'unfollows; Undo brings the face back', (tester) async {
    final favorites = _Favorites([
      _follow('Carlsen, Magnus', 1503014, 2837),
      _follow('Gukesh D', 46616543, 2787, day: 2),
    ]);
    await _pumpSpace(tester, const [], favorites: favorites);
    expect(find.text('Carlsen'), findsOneWidget);

    await tester.longPress(find.text('Carlsen'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Remove from My Space'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Carlsen'), findsNothing);
    expect(find.bySemanticsLabel('Players, 1'), findsOneWidget);
    // The follow stands untouched.
    expect(favorites.unfollows, 0);
    expect(favorites.state.valueOrNull, hasLength(2));

    expect(find.text('Removed from My Space'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Carlsen'), findsOneWidget);
    expect(favorites.unfollows, 0);
    await _drain(tester);
  });

  testWidgets('opening a face records the visit, and the player leads the '
      'row when the user comes back', (tester) async {
    await _pumpSpace(
      tester,
      const [],
      favorites: _Favorites([
        _follow('Carlsen, Magnus', 1503014, 2837),
        _follow('Gukesh D', 46616543, 2787, day: 2),
        _follow('Praggnanandhaa R', 25059530, 2767, day: 3),
      ]),
    );
    double x(String name) => tester.getTopLeft(find.text(name)).dx;
    expect(x('Carlsen'), lessThan(x('Praggnanandhaa')));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MySpaceView)),
    );
    final pragg = spacePlayerIdentity(
      fideId: 25059530,
      name: 'Praggnanandhaa R',
    );
    expect(container.read(spacePlayerVisitsProvider), isEmpty);

    await tester.tap(find.text('Praggnanandhaa'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(container.read(spacePlayerVisitsProvider).keys, [pragg]);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(x('Praggnanandhaa'), lessThan(x('Carlsen')));
    await _drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every group heads the same way, and its name opens what its '
      'See all opens: the See all page, or My Prep on its Openings tab for '
      'Openings', (tester) async {
    await _pumpSpace(tester, [
      _pin(eventSpaceDraft(_feed.first), 'e0', 20),
      _pin(spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'), 'o', 6),
      _folder,
    ]);
    expect(_groupTitles(tester), ['Events', 'Openings', 'Databases']);
    // See all on every group, even one that shows everything it holds.
    final seeAll = find.textContaining('See all', findRichText: true);
    expect(seeAll, findsNWidgets(3));
    final styles = {
      for (final e in seeAll.evaluate()) (e.widget as RichText).text.style,
    };
    expect(styles, hasLength(1), reason: 'one See all, identical everywhere');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    Future<void> settleRoute() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // The name is a node of its own, just the name's line (never the whole
    // group as one button).
    final eventsTitle = find.bySemanticsLabel('Events, 1');
    expect(
      tester.getRect(eventsTitle).height,
      lessThan(
        tester.getSize(find.byType(SpaceDatabaseGroupView).first).height,
      ),
    );
    expect(
      tester
          .getRect(eventsTitle)
          .contains(tester.getCenter(find.text('Events'))),
      isTrue,
    );
    await tester.tap(eventsTitle);
    await settleRoute();
    expect(
      tester
          .widget<SpaceSectionScreen>(find.byType(SpaceSectionScreen))
          .section,
      SpaceSection.events,
    );
    navigator.pop();
    await settleRoute();

    for (final target in [
      find.bySemanticsLabel('Openings, 1'),
      find.bySemanticsLabel('See all 1 Openings'),
    ]) {
      await tester.tap(target);
      await settleRoute();
      final prep = tester.widget<MyPrepScreen>(find.byType(MyPrepScreen));
      expect(MyPrepScreen.tabs[prep.initialTab], 'Openings');
      expect(find.byType(SpaceSectionScreen), findsNothing);
      navigator.pop();
      await settleRoute();
    }
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  for (final mode in GamesListViewMode.values) {
    testWidgets('inside every rail every game is the viewer\'s ${mode.name} '
        'card: live event boards, saved games, saved lines and the games '
        'followed players are playing', (tester) async {
      await _pumpSpace(
        tester,
        [
          _pin(eventSpaceDraft(_feed.first), 'e0', 20),
          _pin(gameSpaceShortcutDraft(_game('g-3', whiteFide: 21))!, 'g3', 9),
          _pin(gameSpaceShortcutDraft(_game('g-4', whiteFide: 22))!, 'g4', 8),
          _pin(
            spaceOpeningDraft(targetId: 'C67', name: 'Berlin Defence'),
            'o1',
            7,
          ),
          _pin(
            spaceOpeningDraft(targetId: 'B90', name: 'Sicilian Najdorf'),
            'o2',
            6,
          ),
        ],
        liveEvents: ['ev-a'],
        eventGames: {
          'ev-a': [
            _game('g-1', whiteFide: 11),
            _game('g-2', whiteFide: 12, blackFide: 13),
          ],
        },
        favorites: _Favorites([_follow('Carlsen, Magnus', 1503014, 2837)]),
        playerGames: [_game('p-1', whiteFide: 1503014, blackFide: 31)],
        mode: mode,
        height: 6000,
      );
      await tester.pump(const Duration(milliseconds: 100));
      final phoneGrid = 390 / 2 - 24;
      Finder rail(String storageId) =>
          find.byKey(PageStorageKey<String>('space_rail_$storageId'));

      for (final (id, count) in [
        ('events', 2),
        ('games', 2),
        ('players_live', 1),
      ]) {
        final grid = find.descendant(
          of: rail(id),
          matching: find.byType(GridGameCardWrapperWidget),
        );
        final cards = tester.widgetList<GameCardWrapperWidget>(
          find.descendant(
            of: rail(id),
            matching: find.byType(GameCardWrapperWidget),
          ),
        );
        switch (mode) {
          case GamesListViewMode.chessBoardGrid:
            expect(grid, findsNWidgets(count), reason: id);
            expect(cards, isEmpty, reason: id);
            // Games that all fit whole stand at the width the grid card
            // has in Discovery.
            for (final e in grid.evaluate()) {
              expect(
                tester.getSize(find.byWidget(e.widget)).width,
                closeTo(phoneGrid, 0.5),
                reason: id,
              );
            }
          case GamesListViewMode.gamesCard:
            expect(grid, findsNothing, reason: id);
            expect(cards, hasLength(count), reason: id);
            expect(cards.every((c) => !c.isChessBoardVisible), isTrue);
          case GamesListViewMode.chessBoard:
            expect(grid, findsNothing, reason: id);
            expect(cards, hasLength(count), reason: id);
            expect(cards.every((c) => c.isChessBoardVisible), isTrue);
        }
      }

      // A saved line lays its position out the same way.
      final lines = find.descendant(
        of: rail('openings'),
        matching: find.byType(SpaceOpeningCard),
      );
      expect(lines, findsNWidgets(2));
      final line = tester.getSize(lines.first);
      switch (mode) {
        case GamesListViewMode.chessBoardGrid:
          expect(line.width, closeTo(phoneGrid, 0.5));
        case GamesListViewMode.gamesCard:
          expect(line.width, greaterThan(phoneGrid + 60));
          expect(line.height, lessThan(line.width / 2));
        case GamesListViewMode.chessBoard:
          expect(line.width, greaterThan(phoneGrid + 60));
          expect(line.height, greaterThan(line.width * 0.8));
      }
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });
  }

  testWidgets('a group loads its next page as its rail nears the end: '
      'followed players sixteen at a time, saved lines ten', (tester) async {
    final favorites = [
      for (var i = 0; i < 25; i++)
        _follow('Player $i, Test', 900000 + i, 2600 + i, day: 1 + i % 27),
    ];
    await _pumpSpace(
      tester,
      [
        for (var i = 0; i < 23; i++)
          _pin(
            spaceOpeningDraft(targetId: 'A${10 + i}', name: 'Line $i'),
            'o$i',
            100.0 - i,
          ),
      ],
      favorites: _Favorites(favorites),
      height: 3000,
    );
    SpaceRail railOf(String id) => tester.widget<SpaceRail>(
      find.byWidgetPredicate((w) => w is SpaceRail && w.storageId == id),
    );
    ScrollPosition positionOf(String id) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(PageStorageKey<String>('space_rail_$id')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    Future<void> toEnd(String id) async {
      final position = positionOf(id);
      position.jumpTo(position.maxScrollExtent);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // The first page only, and the count still names them all.
    expect(railOf('players').items, hasLength(kSpacePlayersRailPage));
    expect(railOf('players').hasMore, isTrue);
    expect(find.bySemanticsLabel('Players, 25'), findsOneWidget);
    expect(railOf('openings').items, hasLength(kSpaceRailPage));

    // A third of the way along: nothing more yet.
    final start = positionOf('players');
    start.jumpTo(start.maxScrollExtent / 3);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(railOf('players').items, hasLength(kSpacePlayersRailPage));

    // Near the end: the next page, and the last.
    await toEnd('players');
    expect(railOf('players').items, hasLength(25));
    expect(railOf('players').hasMore, isFalse);

    await toEnd('openings');
    expect(railOf('openings').items, hasLength(2 * kSpaceRailPage));
    await toEnd('openings');
    expect(railOf('openings').items, hasLength(23));
    expect(railOf('openings').hasMore, isFalse);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  for (final light in [false, true]) {
    testWidgets('the page reads in ${light ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      await _pumpSpace(tester, [
        _folder,
        _player,
      ], theme: light ? AppTheme.lightTheme : AppTheme.darkTheme);
      final colors = light ? AppColors.light : AppColors.dark;
      final title = tester.widget<Text>(
        find.text(_groupTitles(tester).first).first,
      );
      expect(title.style!.color, colors.textPrimary);
      expectNoContrastMisses(
        auditTextContrast(tester, fallbackGround: colors.background),
        where: 'MySpaceView',
      );
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });
  }
}
