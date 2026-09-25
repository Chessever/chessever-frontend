import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
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
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_header.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart'
    show ForYouEventGamesSnapshot;
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart'
    show DiscoveryCardMeta, DiscoveryGameList;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
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

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ..._list]);
  }

  @override
  Future<void> moveToFront(String id) async {}

  @override
  Future<void> markOpened(String id) async {}
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

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
}

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
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = _FakeSpaceShortcuts(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => store),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
        currentUserProvider.overrideWithValue(null),
        likedGamesProvider.overrideWith(_NoLikes.new),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
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
        gamesListViewModeProvider.overrideWithValue(
          GamesListViewMode.chessBoardGrid,
        ),
        eventImageProvider.overrideWith(
          (ref, id) async => const EventImageData(),
        ),
        eventNextRoundProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        // A phone, however tall the test view is (a tall view would read as
        // a tablet).
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const MySpaceView(),
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

void main() {
  testWidgets('an empty space: captioned tiles, My Database with Add, the '
      'explainer, three live events to save, and the Smart Event tile last', (
    tester,
  ) async {
    await _pumpSpace(tester, const []);

    expect(find.text('My Likes'), findsOneWidget);
    expect(find.text('No likes yet'), findsOneWidget);
    expect(find.text('My Prep'), findsOneWidget);
    // A guest's My Prep counts the master database.
    expect(find.text('9.8M master games'), findsOneWidget);
    expect(find.text('My Database'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
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
  });

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
      'streak pins stay out; a group over its cap offers See all', (
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
    // Events: 3 of 4 shown, and See all.
    expect(find.byType(EventCard), findsNWidgets(3));
    final eventsHeader = find.byType(SpaceSectionHeader).first;
    expect(
      (tester.widget(eventsHeader) as SpaceSectionHeader).onSeeAll,
      isNotNull,
    );
    for (final header in find.byType(SpaceSectionHeader).evaluate().skip(1)) {
      expect((header.widget as SpaceSectionHeader).onSeeAll, isNull);
    }
    // A player is a face with a surname, never a pixel row.
    expect(find.text('Carlsen'), findsOneWidget);
    expect(find.text('2837'), findsOneWidget);
    expect(find.byType(SpaceSavedRow), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a saved player\'s game already drawn under a saved live '
      'event is drawn once; the rest read who is at the board', (
    tester,
  ) async {
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

    final boards = tester.widget<DiscoveryGameList>(
      find.byKey(const ValueKey('space_players_live')),
    );
    expect(boards.games.map((g) => g.gameId), ['g-other']);
    final events = tester.widget<DiscoveryGameList>(
      find.byKey(const ValueKey('space_event_games_ev-a')),
    );
    expect(events.games.map((g) => g.gameId), ['g-event']);
    // The line says who is at the board (its words may give way on a
    // narrow card; the whole sentence is always its label).
    final lines = tester.widgetList<DiscoveryCardMeta>(
      find.descendant(
        of: find.byKey(const ValueKey('space_players_live')),
        matching: find.byType(DiscoveryCardMeta),
      ),
    );
    expect(lines.map((l) => l.semanticsLabel), ['Carlsen playing now']);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a saved event is LIVE by the live feed only, never by the '
      'category it was saved with', (tester) async {
    await _pumpSpace(tester, [_pin(eventSpaceDraft(_feed.first), 'e0', 20)]);
    expect(find.text('LIVE'), findsNothing);
    expect(find.byKey(const ValueKey('space_event_games_ev-a')), findsNothing);
    expect(
      spaceEventCardModelFromShortcut(
        eventSpaceDraft(_feed.first),
      ).tourEventCategory,
      TourEventCategory.ongoing,
    );
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('See all is the group at full length, in its own cards, and '
      'orders them in a plain list with handles', (tester) async {
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
    expect(
      find.descendant(
        of: find.byType(SpaceSectionScreen),
        matching: find.byType(EventCard),
      ),
      findsNWidgets(4),
    );

    await tester.tap(find.text('Reorder', findRichText: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(4));
    expect(
      find.descendant(
        of: find.byType(SpaceSectionScreen),
        matching: find.byType(EventCard),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Done', findRichText: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('Add lists the five types', (tester) async {
    await _pumpSpace(tester, [_folder]);

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 600));
    for (final label in ['Event', 'Player', 'Game', 'Opening', 'Database']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
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

  for (final light in [false, true]) {
    testWidgets('the page reads in ${light ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      await _pumpSpace(tester, [
        _folder,
        _player,
      ], theme: light ? AppTheme.lightTheme : AppTheme.darkTheme);
      final colors = light ? AppColors.light : AppColors.dark;
      final title = tester.widget<Text>(find.text('My Database'));
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
