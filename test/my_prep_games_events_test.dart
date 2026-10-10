import 'dart:convert';
import 'dart:io';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_event_section.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_selection.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/game_tree/game_tree_builder.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_db.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A game as ChessEver exports a broadcast: the `Event` tag is the round's,
/// and its own tags name the event it belongs to.
String _broadcast(String black, String result, {String date = '2026.10.08'}) =>
    '''
[Event "1st Azeri Chess Academy Open (Oct 5th - Oct 10th 2026)"]
[Site "250 Patton St Suite H, Houston, TX 77009"]
[Date "$date"]
[Round "6.1"]
[White "Durarbayli, Vasif"]
[Black "$black"]
[Result "$result"]
[WhiteElo "2611"]
[BlackElo "2545"]
[EventDate "2026.10.05"]
[TimeControl "5400+30"]
[BroadcastName "1st Azeri Chess Academy Open"]
[ChessEverTourId "Hw9G5BMW"]
[ChessEverTourSlug "1st-azeri-chess-academy-open"]
[ChessEverGroupBroadcastId "gb_Hw9G5BMW"]
[ChessEverGroupBroadcastName "1st Azeri Chess Academy Open"]
[ChessEverBroadcastSlug "1st-azeri-chess-academy-open"]

1. c4 c5 2. Nf3 Nf6 $result
''';

/// A game as the database holds it from The Week in Chess.
const _archive = '''
[Event "Sharjah Masters 2026"]
[Site "Sharjah UAE"]
[Date "2026.05.20"]
[Round "3"]
[White "Durarbayli,V"]
[Black "Aravindh,Chithambaram VR."]
[Result "1/2-1/2"]
[WhiteElo "2611"]
[BlackElo "2724"]
[EventDate "2026.05.17"]

1. e4 e5 2. Nf3 Nc6 1/2-1/2
''';

String _server(String id, String white, String black, String date) =>
    '''
[Event "Rated blitz game"]
[Site "https://lichess.org/$id"]
[Date "$date"]
[Round "-"]
[White "$white"]
[Black "$black"]
[Result "0-1"]
[WhiteElo "2427"]
[BlackElo "2805"]
[TimeControl "180+0"]

1. d4 d5 2. c4 e6 0-1
''';

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => [];
}

/// The events backend, answering for one broadcast and recording what it
/// was asked for.
class _Broadcasts implements GroupBroadcastRepository {
  final ids = <String>[];
  final slugs = <String>[];

  static final open = GroupBroadcast(
    id: 'gb_Hw9G5BMW',
    createdAt: DateTime.utc(2026, 10, 1),
    name: '1st Azeri Chess Academy Open',
    search: const [],
    dateStart: DateTime.utc(2026, 10, 5),
    dateEnd: DateTime.utc(2026, 10, 10),
    timeControl: 'standard',
  );

  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    ids.add(id);
    if (id == open.id) return open;
    throw StateError('No broadcast $id');
  }

  @override
  Future<GroupBroadcast?> getGroupBroadcastBySlug(String slug) async {
    slugs.add(slug);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A game from the archive in an event of its own, [day] days into March.
String _archiveGame(int day) =>
    '''
[Event "Spring Open $day"]
[Site "Baku AZE"]
[Date "2026.03.${day.toString().padLeft(2, '0')}"]
[Round "1"]
[White "Durarbayli,V"]
[Black "Opponent $day"]
[Result "1-0"]

1. e4 e5 1-0
''';

class _NoFavorites extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => [];
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('prep_events'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Indexes a database file and a Lichess file as one profile does.
  GameTreeStore index() {
    final database = File('${dir.path}/chessever.pgn')
      ..writeAsStringSync(
        [
          _broadcast('Zhou, Jianchao', '1/2-1/2'),
          _broadcast('Putnam, Liam', '1-0', date: '2026.10.10'),
          _archive,
        ].join('\n'),
      );
    final server = File('${dir.path}/lichess.pgn')
      ..writeAsStringSync(
        [
          _server('g1', 'savchess06', 'Durarbayli', '2026.10.09'),
          _server('g2', 'someone', 'Durarbayli', '2026.10.01'),
        ].join('\n'),
      );
    final db = '${dir.path}/profile.sqlite';
    runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: db,
        sources: [
          GameTreeSourceFile(path: database.path, kind: 'chessever'),
          GameTreeSourceFile(path: server.path, kind: 'lichess'),
        ],
        aliases: const ['durarbayli, vasif', 'durarbayli,v', 'durarbayli'],
      ),
    );
    final store = GameTreeStore.open('profile', db, playerScope: true)!;
    addTearDown(store.close);
    return store;
  }

  test('a pool game has no event; a tournament keeps its own name', () {
    for (final pool in const [
      'Rated Blitz game',
      'casual blitz game',
      'Rated Bullet tournament https://lichess.org/tournament/abc',
      'Live Chess',
      "Let's Play!",
      '?',
      '',
    ]) {
      expect(prepEventTitle(event: pool), isNull, reason: pool);
    }
    expect(prepEventTitle(event: 'Rated Rapid Open'), 'Rated Rapid Open');
    expect(
      prepEventTitle(event: 'Titled Tuesday Blitz October 07 2025'),
      'Titled Tuesday Blitz October 07 2025',
    );
    // A broadcast's own name wins over the round its Event tag describes.
    expect(
      prepEventTitle(
        broadcast: 'Norway Chess 2026',
        event: 'Round 7: Carlsen, Magnus - Caruana, Fabiano',
      ),
      'Norway Chess 2026',
    );
    // A pairing label alone still names its tournament by the broadcast link.
    expect(
      prepEventTitle(
        event: 'Round 7: Carlsen, Magnus - Caruana, Fabiano',
        site: 'https://lichess.org/broadcast/norway-chess-2026/round-7/x/y',
      ),
      'Norway Chess 2026',
    );
    expect(
      prepEventTitle(event: 'Round 7: Carlsen, Magnus - Caruana, Fabiano'),
      isNull,
    );
  });

  test('the index keeps what names a game\'s event', () async {
    final rows = await index().loadGames();
    final games = [
      for (final (i, row) in rows.indexed) PrepGame.fromIndex(row, i),
    ];
    expect(games, hasLength(5));

    final open = games.firstWhere((g) => g.black == 'Putnam, Liam');
    expect(open.eventName, '1st Azeri Chess Academy Open');
    expect(open.eventId, 'gb_Hw9G5BMW');
    expect(open.eventSlug, '1st-azeri-chess-academy-open');
    expect(open.eventDate, DateTime.utc(2026, 10, 5));
    expect(open.site, '250 Patton St Suite H, Houston, TX 77009');
    expect(open.round, '6.1');
    expect(open.eventLabel, '1st Azeri Chess Academy Open');
    expect(open.eventKey, '1st azeri chess academy open');

    final archive = games.firstWhere((g) => g.white == 'Durarbayli,V');
    expect(archive.eventName, isNull);
    expect(archive.eventId, isNull);
    expect(archive.eventLabel, 'Sharjah Masters 2026');
    expect(archive.eventKey, 'sharjah masters 2026');

    // A server game falls back to where and how fast it was played, and
    // heads no event card.
    final pool = games.firstWhere((g) => g.white == 'savchess06');
    expect(pool.round, isNull);
    expect(pool.eventTitle, isNull);
    expect(pool.eventLabel, 'Lichess · Blitz');
    expect(pool.eventKey, isNull);
  });

  test('a card prints its event, and only a server game falls back', () async {
    final store = index();
    final rows = await store.loadGames();
    final games = [
      for (final (i, row) in rows.indexed) PrepGame.fromIndex(row, i),
    ];
    final analysis = PrepAnalysis(
      profileId: 'profile',
      games: games,
      store: store,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cards = [
      for (final game in games)
        container.read(prepGameCardProvider((analysis: analysis, game: game)))!,
    ];
    // Newest first. `tourSlug` is the line a game card prints its event from.
    expect(cards.map((card) => card.tourSlug), [
      '1st Azeri Chess Academy Open',
      'Lichess · Blitz',
      '1st Azeri Chess Academy Open',
      'Lichess · Blitz',
      'Sharjah Masters 2026',
    ]);
    // The coin beside it follows the index's clock, not a guess from the name.
    expect(cards.map((card) => card.timeControl), [
      'standard',
      'blitz',
      'standard',
      'blitz',
      'standard',
    ]);
    expect(cards.first.pgn, contains('1. c4 c5'));
  });

  testWidgets('games sit under event cards, each where its first game falls', (
    tester,
  ) async {
    // A phone's own size, so every scaled length is what a device lays out.
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final rows = (await tester.runAsync(index().loadGames))!;
    final games = [
      for (final (i, row) in rows.indexed) PrepGame.fromIndex(row, i),
    ];
    PrepFilter? cleared;
    final controller = PrepGamesController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesListViewModeProvider.overrideWithValue(
            GamesListViewMode.gamesCard,
          ),
          premiumAccessProvider.overrideWithValue(true),
          playerEventCardProvider.overrideWith((ref, request) async => null),
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
          favoriteEventsProvider.overrideWith(_NoFavorites.new),
          eventImageProvider.overrideWith(
            (ref, id) async => const EventImageData(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                // No index behind it: the list is laid out from the light
                // rows alone, which is all its sections read.
                body: PrepGamesTab(
                  analysis: PrepAnalysis(profileId: 'profile', games: games),
                  games: games,
                  filter: const PrepFilter(),
                  onFilterChanged: (filter) => cleared = filter,
                  controller: controller,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Newest first: the open (two games), the server games it is set apart
    // from, then the older event.
    final sections = tester
        .widgetList<PlayerGamesEventSection>(
          find.byType(PlayerGamesEventSection),
        )
        .toList();
    expect(sections.map((s) => s.eventData?.tourName), [
      '1st Azeri Chess Academy Open',
      'Sharjah Masters 2026',
    ]);
    // The broadcast opens by its id; the archive event is found by name.
    expect(sections.first.dataSource, PlayerProfileDataSource.supabase);
    expect(sections.first.tourId, 'gb_Hw9G5BMW');
    expect(sections.first.gameCount, 2);
    expect(sections.first.playerScore, 1.5);
    expect(sections.first.eventData?.startDate, DateTime.utc(2026, 10, 5));
    expect(sections.first.eventData?.endDate, DateTime.utc(2026, 10, 10));
    expect(sections.first.eventData?.site, contains('Houston'));
    expect(sections.last.dataSource, PlayerProfileDataSource.twic);
    expect(sections.last.tourId, 'Sharjah Masters 2026');
    expect(find.textContaining('Lichess   2 games'), findsOneWidget);
    expect(find.text('Loaded all 5 games'), findsOneWidget);
    expect(find.byType(PlayerGamesCollapseToggle), findsNWidgets(3));

    // The screen's menu acts on the games shown, and can turn the list into
    // a pick list as a profile's "Choose games manually" does.
    expect(prepGamesMenu(controller).map((row) => row.label), [
      'Save these 5 games to Library',
      'Choose games to save',
      'Export these 5 games as PGN',
    ]);
    expect(find.byType(PlayerGamesSelectionToolbar), findsNothing);
    controller.chooseGames();
    await tester.pumpAndSettle();
    expect(find.text('Choose games to save'), findsOneWidget);
    expect(find.text('Tap games manually or use quick select'), findsOneWidget);
    expect(find.text('Select first'), findsOneWidget);
    expect(
      prepGamesMenu(controller).map((row) => row.label),
      isNot(contains('Choose games to save')),
    );
    await tester.tap(find.text('Select all (5)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('5 selected'), findsOneWidget);
    expect(find.text('Add selected'), findsOneWidget);
    expect(find.text('Selected 5 filtered games'), findsOneWidget);
    // Let the confirmation leave before the next step.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    // Closing the panel drops the picks.
    await tester.tap(
      find.descendant(
        of: find.byType(PlayerGamesSelectionToolbar),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerGamesSelectionToolbar), findsNothing);
    controller.chooseGames();
    await tester.pumpAndSettle();
    expect(find.text('Choose games to save'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(PlayerGamesSelectionToolbar),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();

    // Searching an event's name keeps only that event, and says so.
    await tester.enterText(find.byType(TextField), 'sharjah');
    await tester.pump();
    expect(find.byType(PlayerGamesEventSection), findsOneWidget);
    expect(find.textContaining('Lichess'), findsNothing);
    expect(find.textContaining('1 filter active · 1 games'), findsOneWidget);
    expect(find.text('Loaded all 1 games'), findsOneWidget);

    // The strip clears the search; there was no filter to hand back.
    await tester.tap(find.textContaining('1 filter active'));
    await tester.pump();
    expect(find.byType(PlayerGamesEventSection), findsNWidgets(2));
    expect(cleared, isNull);
    expect(tester.takeException(), isNull);
  });

  test('an index from before the event columns is rebuilt, not read', () async {
    final store = index();
    final path = store.dbPath;
    expect((await store.loadGames()).first.eventName, isNotNull);
    store.close();

    // Put the file back to the layout the last release wrote: no event
    // columns, and a signature that says version 3.
    final old = openGameTreeDatabase(path);
    for (final column in const [
      'site',
      'round',
      'ev',
      'evid',
      'evslug',
      'evdate',
    ]) {
      old.execute('ALTER TABLE games DROP COLUMN $column');
    }
    final signature =
        jsonDecode(readGameTreeMeta(old, 'signature')!) as Map<String, dynamic>;
    expect(signature['v'], kGameTreeSchemaVersion);
    writeGameTreeMeta(old, 'signature', jsonEncode({...signature, 'v': 3}));
    old.close();

    // It cannot be opened as it is, which is what sends the app to rebuild.
    expect(GameTreeStore.open('profile', path, playerScope: true), isNull);

    final rebuilt = runGameTreeBuild(
      GameTreeBuildRequest(
        dbPath: path,
        sources: [
          GameTreeSourceFile(
            path: '${dir.path}/chessever.pgn',
            kind: 'chessever',
          ),
          GameTreeSourceFile(path: '${dir.path}/lichess.pgn', kind: 'lichess'),
        ],
        aliases: const ['durarbayli, vasif', 'durarbayli,v', 'durarbayli'],
      ),
    );
    expect(rebuilt.rebuilt, isTrue);
    expect(rebuilt.games, 5);
    final again = GameTreeStore.open('profile', path, playerScope: true)!;
    addTearDown(again.close);
    expect(again.isCurrentVersion, isTrue);
    final games = await again.loadGames();
    expect(
      games.where((g) => g.eventId == 'gb_Hw9G5BMW'),
      hasLength(2),
      reason: 'the rebuild indexes what names each game\'s event',
    );
  });

  testWidgets(
    'an event card becomes its broadcast, and a tap opens the event',
    (tester) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final rows = (await tester.runAsync(index().loadGames))!;
      final games = [
        for (final (i, row) in rows.indexed) PrepGame.fromIndex(row, i),
      ];
      final backend = _Broadcasts();
      final container = ProviderContainer(
        overrides: [
          gamesListViewModeProvider.overrideWithValue(
            GamesListViewMode.gamesCard,
          ),
          premiumAccessProvider.overrideWithValue(true),
          // The card's own provider runs: only the backend behind it is a fake.
          groupBroadcastRepositoryProvider.overrideWithValue(backend),
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
          favoriteEventsProvider.overrideWith(_NoFavorites.new),
          eventImageProvider.overrideWith(
            (ref, id) async => const EventImageData(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            routes: {
              '/tournament_detail_screen': (_) =>
                  const Scaffold(body: Center(child: Text('EVENT PAGE'))),
            },
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: PrepGamesTab(
                    analysis: PrepAnalysis(profileId: 'profile', games: games),
                    games: games,
                    filter: const PrepFilter(),
                    onFilterChanged: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The broadcast was asked for by the id its games carry, and the archive
      // event by the slug its name makes.
      expect(backend.ids, contains('gb_Hw9G5BMW'));
      expect(backend.slugs, contains('sharjah-masters-2026'));
      final cards = tester
          .widgetList<EventCard>(find.byType(EventCard))
          .map((card) => card.tourEventCardModel)
          .toList();
      expect(cards.first.id, 'gb_Hw9G5BMW');
      expect(cards.first.eventSource, EventSource.lichessBroadcast);
      expect(cards.first.title, '1st Azeri Chess Academy Open');
      // No broadcast answers for the archive event: it keeps the card built
      // from its own games.
      expect(cards.last.eventSource, EventSource.communityEvent);
      expect(cards.last.title, 'Sharjah Masters 2026');

      expect(container.read(selectedBroadcastModelProvider), isNull);
      await tester.tap(find.text('1st Azeri Chess Academy Open').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('EVENT PAGE'), findsOneWidget);
      expect(container.read(selectedBroadcastModelProvider)?.id, 'gb_Hw9G5BMW');
      expect(
        container.read(selectedTourModeProvider),
        TournamentDetailScreenMode.games,
      );
      // A resolved card is kept for 45 seconds after its last reader; let
      // that run out before the test ends.
      await tester.pump(const Duration(seconds: 46));
    },
  );

  testWidgets(
    'the search row leaves on the way down and returns on the way up',
    (tester) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // Twenty events, a header each: a list several screens long.
      final file = File('${dir.path}/long.pgn')
        ..writeAsStringSync(
          [for (var day = 1; day <= 20; day++) _archiveGame(day)].join('\n'),
        );
      final db = '${dir.path}/long.sqlite';
      runGameTreeBuild(
        GameTreeBuildRequest(
          dbPath: db,
          sources: [GameTreeSourceFile(path: file.path, kind: 'chessever')],
          aliases: const ['durarbayli,v'],
        ),
      );
      final store = GameTreeStore.open('long', db, playerScope: true)!;
      addTearDown(store.close);
      final rows = (await tester.runAsync(store.loadGames))!;
      final games = [
        for (final (i, row) in rows.indexed) PrepGame.fromIndex(row, i),
      ];
      expect(games, hasLength(20));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gamesListViewModeProvider.overrideWithValue(
              GamesListViewMode.gamesCard,
            ),
            premiumAccessProvider.overrideWithValue(true),
            playerEventCardProvider.overrideWith((ref, request) async => null),
            spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
            favoriteEventsProvider.overrideWith(_NoFavorites.new),
            eventImageProvider.overrideWith(
              (ref, id) async => const EventImageData(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: PrepGamesTab(
                    analysis: PrepAnalysis(profileId: 'long', games: games),
                    games: games,
                    filter: const PrepFilter(),
                    onFilterChanged: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final filter = find.byTooltip('Filter and sort games').hitTestable();
      double offset() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(filter, findsOneWidget);
      expect(find.byType(PlayerGamesEventSection), findsWidgets);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(offset(), greaterThan(600));
      expect(
        filter,
        findsNothing,
        reason: 'the row scrolls away with the list',
      );

      // A short pull back brings the row in over the list, far from its top.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(offset(), greaterThan(500));
      expect(filter, findsOneWidget, reason: 'the row floats back in');
      expect(tester.takeException(), isNull);
    },
  );
}
